#!/usr/bin/env python3
"""Convert a captured Claude share snapshot JSON into clean archival files."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def message_text(message: dict) -> str:
    parts = []
    for block in message.get("content", []):
        if block.get("type") == "text" and block.get("text", "").strip():
            parts.append(block["text"].strip())
    if not parts and message.get("text", "").strip():
        parts.append(message["text"].strip())
    return "\n\n".join(parts)


def yaml_string(value: object) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_markdown(snapshot: dict, source_url: str) -> str:
    messages = snapshot.get("chat_messages", [])
    title = snapshot.get("snapshot_name") or "Claude transcript"
    lines = [
        "---",
        f"title: {yaml_string(title)}",
        f"source: {yaml_string(source_url)}",
        f"snapshot_uuid: {yaml_string(snapshot.get('uuid'))}",
        f"conversation_uuid: {yaml_string(snapshot.get('conversation_uuid'))}",
        f"shared_by: {yaml_string(snapshot.get('created_by'))}",
        f"snapshot_created_at: {yaml_string(snapshot.get('created_at'))}",
        f"snapshot_updated_at: {yaml_string(snapshot.get('updated_at'))}",
        f"message_count: {len(messages)}",
        "---",
        "",
        f"# {title}",
        "",
        f"> Shared by {snapshot.get('created_by') or 'unknown'} on Claude. ",
        f"> Original: [{source_url}]({source_url})",
        "",
    ]

    for ordinal, message in enumerate(messages, start=1):
        sender = message.get("sender")
        speaker = snapshot.get("created_by") or "Human" if sender == "human" else "Claude"
        created_at = message.get("created_at", "")
        index = message.get("index")
        uuid = message.get("uuid", "")
        stop_reason = message.get("stop_reason")
        text = message_text(message)

        lines.extend(
            [
                f"## {speaker}",
                "",
                f"<!-- message {ordinal}; source_index={index}; uuid={uuid}; created_at={created_at} -->",
                "",
            ]
        )
        if text:
            lines.extend([text, ""])
        if stop_reason == "user_canceled":
            lines.extend(["> **Note:** Claude’s response was interrupted.", ""])
        elif not text:
            lines.extend(["_No textual content._", ""])
        lines.extend(["---", ""])

    return "\n".join(lines).rstrip() + "\n"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("snapshot", type=Path)
    parser.add_argument("--source-url", required=True)
    parser.add_argument("--output-dir", type=Path, default=Path.cwd())
    parser.add_argument("--prefix", default="claude-transcript")
    args = parser.parse_args()

    snapshot = json.loads(args.snapshot.read_text(encoding="utf-8"))
    args.output_dir.mkdir(parents=True, exist_ok=True)

    markdown_path = args.output_dir / f"{args.prefix}.md"
    json_path = args.output_dir / f"{args.prefix}.json"
    manifest_path = args.output_dir / f"{args.prefix}-manifest.json"

    markdown_path.write_text(
        render_markdown(snapshot, args.source_url), encoding="utf-8"
    )
    json_path.write_text(
        json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    messages = snapshot.get("chat_messages", [])
    manifest = {
        "title": snapshot.get("snapshot_name"),
        "source_url": args.source_url,
        "snapshot_uuid": snapshot.get("uuid"),
        "conversation_uuid": snapshot.get("conversation_uuid"),
        "shared_by": snapshot.get("created_by"),
        "snapshot_created_at": snapshot.get("created_at"),
        "snapshot_updated_at": snapshot.get("updated_at"),
        "message_count": len(messages),
        "human_message_count": sum(m.get("sender") == "human" for m in messages),
        "assistant_message_count": sum(
            m.get("sender") == "assistant" for m in messages
        ),
        "interrupted_response_count": sum(
            m.get("stop_reason") == "user_canceled" for m in messages
        ),
        "attachment_count": sum(len(m.get("attachments", [])) for m in messages),
        "file_count": sum(len(m.get("files", [])) for m in messages),
        "outputs": {
            markdown_path.name: {
                "bytes": markdown_path.stat().st_size,
                "sha256": sha256(markdown_path),
            },
            json_path.name: {
                "bytes": json_path.stat().st_size,
                "sha256": sha256(json_path),
            },
        },
    }
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
