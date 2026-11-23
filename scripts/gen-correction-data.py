#!/usr/bin/env python3
"""纠错训练对生成器（TRAINING-PLAN §11.1 correct-transcript）：中文语料 → macOS TTS → 线上同款
Whisper 回转 → (错误转写, 正确文本) 对。零人工：错误就是真实 ASR 错误。

用法：
  /opt/anaconda3/bin/python3 scripts/gen-correction-data.py --n 300 [--dry]
输出：datasets/sinan-sft/correction.jsonl（alpaca 格式，直接并入 v3 数据集）
  TTS = say -v Tingting（zh_CN）；ASR = build/司南.app/Contents/MacOS/CraWhisper + ggml-small.bin
  （与线上蒸馏完全同模型，错误分布天然一致）。
"""
import json, os, pathlib, random, re, subprocess, sys, tempfile, unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
WHISPER = ROOT / "build/司南.app/Contents/MacOS/CraWhisper"
MODEL = pathlib.Path.home() / "Library/Application Support/司南/Models/ggml-small.bin"
OUT = ROOT / "datasets/sinan-sft/correction.jsonl"
VOICE = "Tingting"

def load_sentences(n):
    # THUCNews 标题（专有名词密集）+ opus100 中文侧（自然散文），各取一半
    sents = []
    arrow = ROOT / ".corpus-cache/thuc_news_title-train.arrow"
    parquet = ROOT / ".corpus-cache/opus100-en-zh.parquet"
    try:
        import pyarrow.ipc as ipc
        if arrow.exists():
            with open(str(arrow), "rb") as f:
                tab = ipc.open_stream(f).read_all()   # 标题库: label + text, 50000 行
            for v in tab.column("text").to_pylist()[: n * 2]:
                if isinstance(v, str):
                    sents.append(v)
    except Exception as e:
        print("title corpus skipped:", e)
    try:
        import pandas as pd
        if parquet.exists():
            df = pd.read_parquet(parquet)
            for v in df["translation"][: n * 2]:
                if isinstance(v, dict) and isinstance(v.get("zh"), str):
                    sents.append(v["zh"])
    except Exception as e:
        print("parquet skipped:", e)
    sents = [re.sub(r"\s+", " ", s).strip() for s in sents]
    sents = [s for s in sents if 8 <= len(s) <= 60 and not re.search(r"[a-zA-Z]{4,}", s)]
    random.seed(42)
    random.shuffle(sents)
    return sents[:n]

def norm(s):
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"[，。！？、；：""''（）《》【】,\.!\?;:\s]+", "", s)
    return s.lower()

def tts(text, wav_path):
    with tempfile.TemporaryDirectory() as td:
        aiff = os.path.join(td, "a.aiff")
        r = subprocess.run(["say", "-v", VOICE, "-o", aiff, text], capture_output=True)
        if r.returncode != 0:
            return False
        r = subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, wav_path], capture_output=True)
        return r.returncode == 0

def asr(wav_path):
    r = subprocess.run([str(WHISPER), str(MODEL), wav_path, "zh"], capture_output=True, text=True, timeout=120)
    return r.stdout.strip()

def main():
    n = int(sys.argv[sys.argv.index("--n") + 1]) if "--n" in sys.argv else 300
    dry = "--dry" in sys.argv
    sents = load_sentences(n * 3)
    print(f"sentences loaded: {len(sents)}")
    if dry:
        for s in sents[:5]:
            print(" ", s)
        return
    made, tried = 0, 0
    out = open(OUT, "w", encoding="utf-8")
    for s in sents:
        if made >= n:
            break
        tried += 1
        with tempfile.TemporaryDirectory() as td:
            wav = os.path.join(td, "a.wav")
            if not tts(s, wav):
                continue
            got = asr(wav)
        got = re.sub(r"^\[[0-9:]{4,8}\]\s*", "", got)   # 去时间戳前缀（训练输入只留纯文本）
        if not got or norm(got) == norm(s):
            continue  # 转对了没有训练价值
        out.write(json.dumps({
            "messages": [
                {"role": "system", "content": "你是中文语音转写校对员。修正转写文本中的同音字、专有名词和标点错误，只输出修正后的文本。"},
                {"role": "user", "content": f"修正这段语音转写：\n{got}"},
                {"role": "assistant", "content": s},
            ]
        }, ensure_ascii=False) + "\n")
        made += 1
        if made % 25 == 0:
            print(f"{made} pairs (tried {tried})", flush=True)
    out.close()
    print(f"DONE: {made} correction pairs from {tried} sentences -> {OUT}")

if __name__ == "__main__":
    main()
