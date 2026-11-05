"""Build the preserved BitBird GBA source without a development-repo dependency.

SPDX-License-Identifier: GPL-3.0-only
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def project_references(project):
    """Resolve QSF/QIP source references recursively, without Tcl execution."""
    checked = set()
    references = []
    def visit(path):
        path = path.resolve()
        require(path.is_relative_to(project.resolve()), f"External project dependency: {path}")
        require(path.is_file(), f"Missing project dependency: {path}")
        if path in checked:
            return
        checked.add(path)
        text = path.read_text(encoding="utf-8-sig")
        for line in text.splitlines():
            match = re.match(r"set_global_assignment\b.*? -name (\w+)\s+(.+)$", line)
            if not match:
                continue
            kind, value = match.groups()
            if kind not in {"SYSTEMVERILOG_FILE", "VERILOG_FILE", "SDC_FILE", "QIP_FILE", "MIF_FILE", "HEX_FILE", "PRE_FLOW_SCRIPT_FILE"}:
                continue
            joined = re.fullmatch(r'\[file join \$::quartus\(qip_path\) "([^"]+)"\]', value)
            if joined:
                value = joined[1]
            else:
                require(not any(c in value for c in "$[]"), f"Unsupported dependency expression: {line}")
                value = value.strip('"')
            if kind == "PRE_FLOW_SCRIPT_FILE":
                require(value.startswith("quartus_sh:"), "Unknown pre-flow script tool")
                value = value.split(":", 1)[1]
            dependency = (path.parent / value).resolve()
            require(dependency.is_relative_to(project.resolve()), f"External dependency: {dependency}")
            require(dependency.is_file(), f"Missing dependency: {dependency}")
            references.append(dependency.relative_to(project).as_posix())
            if kind == "QIP_FILE":
                visit(dependency)
    visit(project / "src/fpga/ap_core.qsf")
    return sorted(set(references))


def timing_coverage(report):
    text = report.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n")
    coverage = []
    minima = {}
    for match in re.finditer(r"^; ([^;\n]+) Model (Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\s*;", text, re.M):
        corner, kind = match[1].strip(), match[2]
        block = text[match.end():].split("\n\n", 1)[0]
        for row in re.finditer(r"^;\s*([^;\n]+);\s*(-?\d+\.\d+)\s*;\s*(-?\d+\.\d+)\s*;", block, re.M):
            clock, slack, tns = row[1].strip(), float(row[2]), float(row[3])
            require(slack >= 0 and tns == 0, f"Timing failure: {corner}, {kind}, {clock}: {slack}, TNS {tns}")
            coverage.append([corner, kind, clock])
            minima[kind] = min(minima.get(kind, slack), slack)
    require(coverage, "No timing summary rows")
    return sorted(coverage), minima


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True, help="Fresh output directory; never overwritten")
    parser.add_argument("--quartus-bin", type=Path, help="Quartus 18.1 bin/bin64 directory; otherwise use QUARTUS_BIN or PATH")
    parser.add_argument("--prepare-only", action="store_true", help="Verify/copy inputs without invoking Quartus")
    parser.add_argument("--stage-timeout", type=int, default=3600)
    args = parser.parse_args()
    require(args.stage_timeout >= 30, "Stage timeout must be at least 30 seconds")
    run = args.run.resolve()
    require(not run.exists(), "Run directory already exists; choose a new prefix")
    require(not ROOT.is_relative_to(run), "Run directory cannot contain the repository")
    suffix = ".exe" if os.name == "nt" else ""
    tool_dir = args.quartus_bin or (Path(os.environ["QUARTUS_BIN"]) if os.environ.get("QUARTUS_BIN") else None)
    def tool(name):
        path = (tool_dir / (name + suffix)) if tool_dir else shutil.which(name)
        require(path and Path(path).is_file(), f"Missing {name}; set --quartus-bin, QUARTUS_BIN or PATH")
        return str(Path(path).resolve())
    tools = {} if args.prepare_only else {name: tool(name) for name in ("quartus_sh", "quartus_map", "quartus_fit", "quartus_sta", "quartus_asm")}
    manifest = read(ROOT / "docs/candidate-manifest.json")
    for row in manifest["files"]:
        require(digest(ROOT / row["path"]) == row["sha256"], f"Preserved input changed: {row['path']}")
    audit_manifest = read(ROOT / "scripts/timing/audit-manifest.json")
    for row in audit_manifest["files"]:
        require(digest(ROOT / row["path"]) == row["sha256"], f"Audit script changed: {row['path']}")
    run.mkdir(parents=True)
    receipt = {"status": "PREPARING", "stages": {}, "installed": False, "hardware_accepted": False,
               "release_qualified": False, "scope": "Preserved source compile, fitted timing and physical audits; no new simulation or hardware acceptance"}
    def save():
        temporary = run / "receipt.json.tmp"
        temporary.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
        temporary.replace(run / "receipt.json")
    def stage(name, command, timeout, marker=None):
        receipt["status"] = "RUNNING"
        receipt["current_stage"] = name
        save()
        started = time.monotonic()
        print(f"START: {name}", flush=True)
        log = run / (name + ".log")
        with log.open("w", encoding="utf-8") as output:
            process = subprocess.Popen(command, cwd=project / "src/fpga", stdout=output, stderr=subprocess.STDOUT)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                else:
                    process.kill()
                process.wait()
                raise RuntimeError(f"Timeout in {name}; see {log}")
        text = log.read_text(encoding="utf-8", errors="replace")
        receipt["stages"][name] = {"exit_code": code, "seconds": round(time.monotonic() - started, 2), "log": log.name}
        save()
        require(code == 0 and (not marker or marker in text), f"Failed {name}; see {log}")
        require(not re.search(r"(?m)^Error[: (]|Out of memory in module", text), f"Error in {name}; see {log}")
        print(f"PASS: {name}", flush=True)
        return text
    try:
        project = run / "project"
        shutil.copytree(ROOT / "src", project / "src")
        shutil.copytree(ROOT / "scripts/timing", run / "audits")
        sources = [{"path": f.relative_to(project).as_posix(), "sha256": digest(f)} for f in sorted((project / "src").rglob("*")) if f.is_file()]
        (run / "source-manifest.json").write_text(json.dumps(sources, indent=2) + "\n", encoding="utf-8")
        references = project_references(project)
        receipt["project_references"] = len(references)
        receipt["source_files"] = len(sources)
        receipt["build_id_policy"] = "Preserve the sealed build_id.mif/ver bytes; invoke map/fit/sta directly without timestamp pre-flow regeneration"
        receipt["source_manifest_sha256"] = digest(run / "source-manifest.json")
        if args.prepare_only:
            receipt["status"] = "PREPARED"
            save()
            print(f"PREPARED: {len(sources)} source files, {len(references)} recursive project references; no compiler run", flush=True)
            return
        version = stage("tool-version", [tools["quartus_sh"], "--version"], 30)
        require(re.search(r"Version 18\.1(?:\.|\s)", version), "Expected Quartus 18.1; no source/build setting changes are authorized")
        for name, marker in (("map", "Analysis & Synthesis"), ("fit", "Fitter"), ("sta", "Timing Analyzer")):
            stage(name, [tools["quartus_" + name], "ap_core"], args.stage_timeout, f"Quartus Prime {marker} was successful.")
        output = project / "src/fpga/output_files"
        coverage, minima = timing_coverage(output / "ap_core.sta.rpt")
        require(coverage == audit_manifest["timing_coverage"], "Missing or changed fitted clock/corner timing coverage")
        receipt["timing_minima_ns"] = minima
        save()
        for audit in audit_manifest["audits"]:
            prefix = run / audit["name"]
            command = [tools["quartus_sta"], "-t", str(run / "audits" / audit["script"]), str(prefix)] + audit.get("arguments", [])
            stage(audit["name"], command, 240, audit.get("marker"))
            proof = read(prefix.with_suffix(".json"))
            require(proof.get("corners") == 4, f"Incomplete physical audit: {audit['name']}")
            if audit["name"] == "diagnosis":
                require(proof.get("status") == "MEASURED" and proof["minimum_setup_ns"] >= 0, "Diagnosis audit failed")
            else:
                require(proof.get("status", "PASS") == "PASS", f"Physical audit failed: {audit['name']}")
        fit = (output / "ap_core.fit.rpt").read_text(encoding="utf-8", errors="replace")
        headers, pins = [], {}
        for line in fit.splitlines():
            cells = [s.strip() for s in line.split(";")[1:-1]]
            if cells and cells[0] == "Name" and "Output Enable Register" in cells:
                headers = cells
            elif headers and cells and cells[0].startswith("dram_dq[") and len(cells) == len(headers):
                pins[cells[0]] = cells[headers.index("Output Enable Register")]
        require(set(pins) == {f"dram_dq[{i}]" for i in range(16)} and all(v == "yes" for v in pins.values()), "SDRAM output-enable register packing failed")
        require(re.search(r"cache_data_ram[^\n]*;\s*M10K(?: block)?\s*;", fit), "EWRAM cache data M10K mapping missing")
        stage("asm", [tools["quartus_asm"], "ap_core"], args.stage_timeout, "Quartus Prime Assembler was successful.")
        for row in sources:
            require(digest(project / row["path"]) == row["sha256"], f"Compiler changed preserved input: {row['path']}")
        raw = (output / "ap_core.rbf").read_bytes()
        table = bytes(int(f"{i:08b}"[::-1], 2) for i in range(256))
        image = run / "bitstream.rbf_r"
        image.write_bytes(raw.translate(table))
        require(image.read_bytes().translate(table) == raw, "Bit-reversal readback failed")
        receipt.update(status="PASS", physical_audits=len(audit_manifest["audits"]), image_sha256=digest(image), image_bytes=image.stat().st_size,
                       equals_preserved_image=digest(image) == manifest["image_sha256"], image_generated=True)
        receipt.pop("current_stage", None)
        save()
        print(f"COMPLETE: build and {len(audit_manifest['audits'])} audits PASS; {image}; release/hardware acceptance separate", flush=True)
    except Exception as error:
        receipt.update(status="FAILED", error=str(error))
        save()
        raise


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"FAILED: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
