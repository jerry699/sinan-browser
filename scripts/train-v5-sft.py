#!/usr/bin/env python3
"""司南 v3 SFT（correct-transcript 等 7 任务的浏览领域模型）——纯 transformers+peft，无 llamafactory。

数据: /root/autodl-tmp/train-v5.jsonl（messages: system/user/assistant）
基座: /root/.cache/modelscope/hub/models/Qwen/Qwen3-0.6B（modelscope 快照）
输出: /root/autodl-tmp/sinan-v5-lora（LoRA 适配器，后续合并→GGUF）
"""
import json, pathlib
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, Trainer, TrainingArguments

BASE = "/root/.cache/modelscope/hub/models/Qwen/Qwen3-0.6B"
DATA = "/root/autodl-tmp/train-v5.jsonl"
OUT = "/root/autodl-tmp/sinan-v5-lora"

tok = AutoTokenizer.from_pretrained(BASE)
model = AutoModelForCausalLM.from_pretrained(BASE, torch_dtype=torch.bfloat16, device_map="cuda")

rows = [json.loads(l) for l in open(DATA)]
print(f"rows: {len(rows)}")

def encode(row):
    ids = tok.apply_chat_template(row["messages"], tokenize=True)
    # 训练信号只在 assistant 回复上：把 prompt 部分的 label 置 -100
    text_prefix = tok.apply_chat_template(row["messages"][:2], tokenize=True)
    labels = list(ids)
    for i in range(min(len(text_prefix), len(labels))):
        labels[i] = -100
    return {"input_ids": ids[:1024], "labels": labels[:1024]}

class DS(torch.utils.data.Dataset):
    def __init__(self, rows):
        self.rows = [encode(r) for r in rows]
    def __len__(self):
        return len(self.rows)
    def __getitem__(self, i):
        return self.rows[i]

def collate(batch):
    n = max(len(b["input_ids"]) for b in batch)
    ids = torch.full((len(batch), n), tok.pad_token_id or 0)
    labels = torch.full((len(batch), n), -100)
    mask = torch.zeros(len(batch), n, dtype=torch.long)
    for i, b in enumerate(batch):
        k = len(b["input_ids"])
        ids[i, :k] = torch.tensor(b["input_ids"])
        labels[i, :k] = torch.tensor(b["labels"])
        mask[i, :k] = 1
    return {"input_ids": ids, "labels": labels, "attention_mask": mask}

from peft import LoraConfig, get_peft_model
cfg = LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05, target_modules="all-linear",
                 task_type="CAUSAL_LM")
model = get_peft_model(model, cfg)
model.enable_input_require_grads()   # 梯度检查点要求输入携带梯度
model.print_trainable_parameters()

args = TrainingArguments(
    output_dir=OUT, per_device_train_batch_size=8, gradient_accumulation_steps=2,
    num_train_epochs=3, learning_rate=2e-4, bf16=True, logging_steps=25,
    save_strategy="no", report_to=[], lr_scheduler_type="cosine",
    warmup_ratio=0.03, seed=42, gradient_checkpointing=True,
)
Trainer(model=model, args=args, train_dataset=DS(rows), data_collator=collate).train()
model.save_pretrained(OUT)
tok.save_pretrained(OUT)
print("TRAIN DONE ->", OUT)
