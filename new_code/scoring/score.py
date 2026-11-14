# Scores recalls with an LLM against Mesoudi's 56 propositions.
#   uv run --env-file .env score.py          (run from new_code/scoring/)
# uv reads the block below and installs that Python and package just for this script.
# --env-file loads ANTHROPIC_API_KEY from the gitignored .env
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["anthropic>=1,<2", "openpyxl"]
# ///

import copy
import csv
import hashlib
import json
import os
import random
import statistics
from concurrent.futures import ThreadPoolExecutor
from string import Template
import urllib.request

import anthropic
import openpyxl

# Which recalls to score: "pilot" (compared with the hand codes) or "mesoudi" (compared with his scores)
SOURCE = "pilot"
# Which model scores: "claude" (3 runs, majority vote) or "gemma" (1 run on this Mac through ollama)
SCORER = "gemma"

# The rubric, shared with coding_sheet.R so the human and model coding read the same propositions
RUBRIC_PATH = "propositions.csv"
PROMPT_PATH = "prompt.txt"

# The pilot recalls and the key that names them R01, R02, ...
EXPORT_PATH = "../whispers/exports/whispers_responses.json"
KEY_PATH = "../whispers/exports/coding_key_pilot.csv"
# Each finished run is added here as one line, so runs already paid for aren't lost if the script stops.
# One log per source, in the gitignored exports folder because the quotes are participant text
RUNS_PATH = f"../whispers/exports/llm_runs_{SOURCE}_{SCORER}.jsonl"
# The hand codes: the coding Google Sheet downloaded as .xlsx, and the tab to compare against
CODED_PATH = "../whispers/exports/coded_pilot.xlsx"
CODER_TAB = "Justin"

# Mesoudi's 40 Experiment 2 recalls, which he shared privately (gitignored folder). The .txt was
# made from his Word file with: textutil -convert txt all_results_gossip4.doc
MESOUDI_RECALLS_PATH = "../../original_code/mesoudi_supplements/all_results_gossip4.txt"
# His published scores for them, from his public GitHub repo
MESOUDI_SCORES_PATH = "../../original_code/mesoudi_whiten_dunbar_2006/mesoudi2006_exp2_data.csv"

# The model and settings from the prereg. The SDK is kept below 2.0 because 2.0
# switches to the API version that rejects temperature, and the prereg says temperature 0
MODEL = "claude-opus-4-6"
GEMMA_MODEL = "gemma4:26b-a4b-it-q4_K_M"
OLLAMA_URL = "http://localhost:11434/api/chat"
TEMPERATURE = 0
MAX_TOKENS = 8000  # 56 answers with quotes come to about 1,500 tokens, so plenty of room
# One run per seed, each in a different shuffled order. Gemma gives the same answer every time
# at temperature 0, so it runs once, in the same order as Claude's first run
SEEDS = [1, 2, 3] if SCORER == "claude" else [1]

# The shape the answer must take. The API enforces it, so the reply is always valid JSON
ANSWER_SCHEMA = {
    "type": "object",
    "properties": {
        "answers": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "id": {"type": "string"},
                    "present": {"type": "boolean"},
                    "quote": {"type": "string"},
                },
                "required": ["id", "present", "quote"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["answers"],
    "additionalProperties": False,
}

# Calls sent at once. Each Claude call takes 15-20 seconds, so 5 at a time scores the pilot in about
# 2 minutes. Gemma runs one at a time, since one call already uses all of this Mac's GPU
PARALLEL_CALLS = 5 if SCORER == "claude" else 1

# Opus 4.6 prices in dollars per million tokens, to work out what each call cost
INPUT_PRICE = 5
OUTPUT_PRICE = 25

# Cost limits. The estimate is the average cost of the runs so far, or this guess before
# there are any (R09 cost $0.039, rounded up). A run stops once it has spent RUN_CAP,
# so a bug can't use up the lab's $100 a month
FIRST_GUESS_PER_CALL = 0.05
RUN_CAP = 15.00


# Mesoudi's 40 recalls from all_results_gossip4, as {code: recall}. The file runs F1-F4 for
# chain 1, then F1-F4 for chain 2, and so on, so each "F1" line starts the next chain.
# Codes are like C03G2: chain 3, generation 2, matching the chain and generation in his CSV
def load_mesoudi_recalls(path):
    recalls, chain, gen, lines = {}, 0, None, []
    for line in open(path).read().splitlines() + ["F1"]:  # a last "F1" closes the final recall
        if line.strip() in ("F1", "F2", "F3", "F4"):
            if gen:
                recalls[f"C{chain:02d}G{gen}"] = "\n\n".join(l.strip() for l in lines if l.strip())
            gen, lines = int(line.strip()[1]), []
            chain += gen == 1
        elif not line.startswith("Chain"):
            lines.append(line)
    return recalls


# A short code made from the prompt and model settings. It changes whenever either one
# changes, so runs scored with an older prompt aren't reused
def run_version(prompt_text):
    model = MODEL if SCORER == "claude" else GEMMA_MODEL
    return hashlib.sha256(f"{model}|{TEMPERATURE}|{prompt_text}".encode()).hexdigest()[:12]


# Every line of the run log, or nothing if there's no log yet
def read_log(path):
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f]


# The runs already saved under this version, as {(recall code, seed): answers}.
# JSON saves each (present, quote) pair as a list, so it's turned back into a pair
def load_runs(log, version):
    return {
        (run["recall"], run["seed"]): {pid: tuple(a) for pid, a in run["answers"].items()}
        for run in log if run["version"] == version
    }


# Shows what a run will cost and asks before spending anything. The estimate is the
# average real cost of every run in the log, under any prompt version
def confirm_cost(calls, log):
    if SCORER == "gemma":
        print(f"{calls} calls, free, ~{calls * 50 // 60 + 1} minutes")
    else:
        per_call = sum(run["cost"] for run in log) / len(log) if log else FIRST_GUESS_PER_CALL
        print(f"{calls} calls to make, about ${calls * per_call:.2f} (${per_call:.3f} each). Stops at ${RUN_CAP:.2f}.")
    if input("Type yes to start: ").strip().lower() != "yes":
        raise SystemExit("Stopped, nothing spent.")


# Turns a rubric row into its id, e.g. "gossip_7"
def proposition_id(row):
    return f"{row['material']}_{row['number']}"


# Some notation points at another proposition by its number within the paragraph
# ("PROMISE, PROFESSOR, NANCY, 7"). Spelling it out as [gossip_7] keeps it
# readable after the propositions are shuffled
def spell_out_references(row):
    parts = [part.strip() for part in row["proposition"].split(",")]
    parts = [f"[{row['material']}_{part}]" if part.isdigit() else part for part in parts]
    return ", ".join(parts)


# One line per proposition, in the order given: id | notation | plain words
def proposition_lines(rubric):
    return "\n".join(
        f"{proposition_id(row)} | {spell_out_references(row)} | {row['point']}" for row in rubric
    )


# One Gemma call through ollama on this Mac: the same prompt and answer form as Claude, at
# temperature 0. Its hidden thinking is turned off, which keeps it fair against Claude
# (no extended thinking either). Each call takes about 50 seconds, almost all of it writing
# the 56 answers at about 26 tokens a second
def ask_gemma(prompt, ids):
    # Gemma's answer form also lists the 56 real ids and fixes the list at 56 entries, because without
    # that it sometimes keeps going after the last one and invents gossip_15, gossip_16, ...
    schema = copy.deepcopy(ANSWER_SCHEMA)
    schema["properties"]["answers"]["items"]["properties"]["id"]["enum"] = ids
    schema["properties"]["answers"]["minItems"] = schema["properties"]["answers"]["maxItems"] = len(ids)
    body = json.dumps({
        "model": GEMMA_MODEL,
        "messages": [{"role": "user", "content": prompt}],
        "format": schema,
        "options": {"temperature": TEMPERATURE},
        "think": False,
        "stream": False,
    }).encode()
    request = urllib.request.Request(OLLAMA_URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.load(response)["message"]["content"]


# One scoring call: the rubric in a shuffled order, the recall, and the model's answer
# as {id: (present, quote)}, plus what the call cost
def score_once(client, prompt_template, rubric, recall, shuffle_seed):
    shuffled = random.Random(shuffle_seed).sample(rubric, len(rubric))
    prompt = prompt_template.substitute(propositions=proposition_lines(shuffled), recall=recall)
    if SCORER == "gemma":
        text, cost = ask_gemma(prompt, [proposition_id(row) for row in rubric]), 0.0
    else:
        response = client.messages.create(
            model=MODEL,
            max_tokens=MAX_TOKENS,
            messages=[{"role": "user", "content": prompt}],
            output_config={"format": {"type": "json_schema", "schema": ANSWER_SCHEMA}},
            # the 1.x SDK no longer takes temperature as an argument, so it goes in the request as is
            extra_body={"temperature": TEMPERATURE},
        )
        text = next(block.text for block in response.content if block.type == "text")
        usage = response.usage
        cost = (usage.input_tokens * INPUT_PRICE + usage.output_tokens * OUTPUT_PRICE) / 1_000_000
    answers = {a["id"]: (a["present"], a["quote"]) for a in json.loads(text)["answers"]}
    return answers, cost


# Adds one finished run to the log
def save_run(path, version, code, seed, answers, cost):
    with open(path, "a") as f:
        f.write(json.dumps({"version": version, "recall": code, "seed": seed,
                            "answers": answers, "cost": cost}) + "\n")


# Problems with an answer: ids missing or extra, and quotes that aren't really in the recall
def check_answers(answers, rubric, recall):
    problems = []
    expected = {proposition_id(row) for row in rubric}
    if set(answers) != expected:
        problems.append(f"missing {sorted(expected - set(answers))}, extra {sorted(set(answers) - expected)}")
    # the model sometimes copies a curly ’ as a straight ', so quote marks are matched either way
    straight = str.maketrans("‘’“”", "''\"\"")
    for pid, (present, quote) in answers.items():
        if present and quote.translate(straight) not in recall.translate(straight):
            problems.append(f"{pid}: quote not found in recall: {quote!r}")
    return problems


# The hand codes from one tab of the coding sheet, as {recall code: {id: True/False}}.
# The sheet's columns are the plain-language points, so each is matched back to its id
def load_hand_codes(path, tab, rubric):
    sheet = openpyxl.load_workbook(path, read_only=True)[tab]
    header, *rows = sheet.iter_rows(values_only=True)
    id_for_point = {row["point"]: proposition_id(row) for row in rubric}
    codes = {}
    for values in rows:
        cells = dict(zip(header, values))
        if not cells["recall"]:
            continue  # formatted but empty rows below the last recall
        codes[cells["recall"]] = {id_for_point[point]: cells[point] == 1 for point in id_for_point}
    return codes


# The runs combined into one answer per proposition: present if more than half said so, which is
# 2 of 3 for Claude and 1 of 1 for Gemma. Each answer is (present, quote, votes). The quote kept is the
# first one from a run that said present, and votes is how many runs said present, so close calls show
def majority(runs):
    combined = {}
    for pid in runs[0]:
        yes = [quote for present, quote in (run[pid] for run in runs) if present]
        combined[pid] = (len(yes) * 2 > len(runs), yes[0] if yes else "", len(yes))
    return combined


# Each recall's 3 runs combined into one answer, for the recalls with all 3 runs done
def combined_answers(runs, recalls, rubric):
    combined = {}
    for code in recalls:
        if all((code, seed) in runs for seed in SEEDS):
            # a run that skipped a proposition counts as not present for it
            filled = [{proposition_id(row): runs[(code, seed)].get(proposition_id(row), (False, ""))
                       for row in rubric} for seed in SEEDS]
            combined[code] = majority(filled)
    return combined


# Prints how often the model and the hand codes agree, then every disagreement with the model's
# quote and votes, so each one can be ruled on
def compare(combined, hand, recalls, rubric):
    pairs = [(hand[code][pid], combined[code][pid][0]) for code in combined for pid in combined[code]]
    both = sum(h and m for h, m in pairs)
    print(f"\nAgreement on {len(pairs)} calls: {sum(h == m for h, m in pairs) / len(pairs):.1%}")
    print(f"  both present {both}, hand only {sum(h and not m for h, m in pairs)}, "
          f"model only {sum(m and not h for h, m in pairs)}")
    for code in sorted(combined):
        for row in rubric:
            pid = proposition_id(row)
            present, quote, votes = combined[code][pid]
            if present != hand[code][pid]:
                who = "model only" if present else "hand only"
                print(f"\n{code} {pid} ({row['point']}): {who}, {votes}/{len(SEEDS)} runs said present")
                print(f"  recall: {recalls[code]}")
                if quote:
                    print(f"  quote: {quote!r}")


# Mesoudi's published scores as {recall code: {material: propositions correct}}
def load_mesoudi_scores(path):
    scores = {}
    with open(path) as f:
        for row in csv.DictReader(f):
            code = f"C{int(row['chain']):02d}G{row['generation']}"
            scores.setdefault(code, {})[row["material"]] = int(row["correct_recall"])
    return scores


# A chain's social minus non-social difference, the number the confirmatory test uses:
# (gossip + social) / 2 - (individual + physical) / 2, averaged over its 4 generations
def chain_difference(totals):
    return statistics.mean((t["gossip"] + t["social"]) / 2 - (t["individual"] + t["physical"]) / 2 for t in totals)


# Compares the model's paragraph totals with Mesoudi's, the way the prereg checks the scorer:
# the correlation of the paragraph totals, and how far apart each chain's difference is.
# His scores are counts per paragraph, so the model's answers are counted the same way
def compare_totals(combined, scores, recalls):
    model = {code: {m: sum(present for pid, (present, _, _) in answers.items() if pid.split("_")[0] == m)
                    for m in scores[code]}
             for code, answers in combined.items()}
    pairs = [(scores[code][m], model[code][m]) for code in sorted(model) for m in scores[code]]
    his, its = zip(*pairs)
    print(f"\n{len(pairs)} paragraph totals: r = {statistics.correlation(his, its):.2f}, "
          f"mean gap {statistics.mean(abs(a - b) for a, b in pairs):.2f} propositions "
          f"(Mesoudi averages {statistics.mean(his):.1f}, the model {statistics.mean(its):.1f})")

    # each chain's difference, only for chains with all 4 generations scored
    gaps = []
    print("\nchain   Mesoudi D   model D   gap")
    for chain in sorted({code[:3] for code in model}):
        codes = [f"{chain}G{g}" for g in range(1, 5)]
        if all(code in model for code in codes):
            his_d = chain_difference([scores[code] for code in codes])
            its_d = chain_difference([model[code] for code in codes])
            gaps.append(abs(his_d - its_d))
            print(f"{chain}     {his_d:6.2f}     {its_d:6.2f}   {gaps[-1]:.2f}")
    if gaps:
        print(f"mean gap in D: {statistics.mean(gaps):.2f} propositions (prereg bar: 0.5 or less)")

    # the paragraphs that are off by 2 or more, to look at
    for code in sorted(model):
        for m in scores[code]:
            if abs(scores[code][m] - model[code][m]) >= 2:
                print(f"\n{code} {m}: Mesoudi {scores[code][m]}, model {model[code][m]}")
                print(f"  recall: {recalls[code]}")


# Load the rubric and the prompt
with open(RUBRIC_PATH) as f:
    rubric = list(csv.DictReader(f))
with open(PROMPT_PATH) as f:
    prompt_text = f.read()
prompt_template = Template(prompt_text)

# Load the recalls by code: the pilot's R01, R02, ... or Mesoudi's C01G1, C01G2, ...
if SOURCE == "pilot":
    with open(EXPORT_PATH) as f:
        rows = {row["id"]: row for row in json.load(f)}
    with open(KEY_PATH) as f:
        recalls = {line["recall"]: rows[line["id"]]["recall_raw"] for line in csv.DictReader(f)}
else:
    recalls = load_mesoudi_recalls(MESOUDI_RECALLS_PATH)

# The runs already done under this prompt, and the ones still to do
version = run_version(prompt_text)
log = read_log(RUNS_PATH)
runs = load_runs(log, version)
todo = [(code, seed) for code in sorted(recalls) for seed in SEEDS if (code, seed) not in runs]

# Score what's left in groups of PARALLEL_CALLS: send a group, wait for all of it, save it,
# then check the cap before sending the next. A run can go at most one group past the cap
if todo:
    confirm_cost(len(todo), log)
    client = anthropic.Anthropic()
    spent = 0.0
    for start in range(0, len(todo), PARALLEL_CALLS):
        if spent >= RUN_CAP:
            print(f"Reached the ${RUN_CAP:.2f} cap. Run again to continue where it left off.")
            break
        group = todo[start:start + PARALLEL_CALLS]
        with ThreadPoolExecutor(max_workers=PARALLEL_CALLS) as pool:
            calls = [pool.submit(score_once, client, prompt_template, rubric, recalls[code], seed)
                     for code, seed in group]
        for (code, seed), call in zip(group, calls):
            try:
                answers, cost = call.result()
            except Exception as error:
                # failed calls are skipped and doesn't cause script to crash, so calls still in progress are saved
                print(f"{code} run {seed}: failed ({error}). Run again to retry it.")
                continue
            spent += cost
            save_run(RUNS_PATH, version, code, seed, answers, cost)
            runs[(code, seed)] = answers
            print(f"{code} run {seed}: {sum(present for present, _ in answers.values())} present, "
                  f"${cost:.3f} (total ${spent:.2f})")
            for problem in check_answers(answers, rubric, recalls[code]):
                print("   ", problem)
print(f"{len(runs)} of {len(recalls) * len(SEEDS)} runs done under prompt version {version}")

# Compare the finished recalls with the hand codes (pilot) or with Mesoudi's scores
combined = combined_answers(runs, recalls, rubric)
if SOURCE == "pilot":
    compare(combined, load_hand_codes(CODED_PATH, CODER_TAB, rubric), recalls, rubric)
elif combined:
    compare_totals(combined, load_mesoudi_scores(MESOUDI_SCORES_PATH), recalls)
