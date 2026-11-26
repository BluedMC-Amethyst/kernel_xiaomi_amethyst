#!/usr/bin/env python3
"""BluedMC AutoFDO converter: kernel IP samples -> LLVM sample profile (no LBR/ETM needed).

amethyst has no ETM/SPE driver and llvm-profgen needs branch records, so this does what Google
AutoFDO's sample-only mode does:
  1. read sampled kernel addresses + counts (simpleperf `report --sort vaddr_in_file -n` output,
     or a plain "<hex addr> <count>" list)
  2. undo KASLR (runtime _text from /proc/kallsyms vs vmlinux System.map)
  3. symbolize every address with llvm-symbolizer (inline chain, function start line, discriminator)
  4. per source line, take the MAX sample count of its instructions (AutoFDO's estimate of how often
     that line runs), nest inlined callees under their call sites
  5. write LLVM's text sample-profile format; llvm-profdata turns it into the extbinary .afdo

usage: afdo_convert.py --vmlinux vmlinux --sysmap System.map --report report_vaddr.txt
                       [--kallsyms kallsyms_text.txt] --symbolizer llvm-symbolizer
                       --profdata llvm-profdata --out bluedmc.afdo [--min-count 2]
The profile only steers inlining/layout decisions; a poor profile costs performance, never
correctness, and the KMI gate still checks every build.
"""
import argparse, collections, json, re, subprocess, sys

def read_sysmap(path):
    syms = {}
    for line in open(path):
        p = line.split()
        if len(p) >= 3 and p[2] in ("_text", "_stext", "_etext"):
            syms[p[2]] = int(p[0], 16)
    return syms

def read_samples(path):
    """simpleperf report (--sort vaddr_in_file -n): '<overhead>% <samples> <0xaddr>' or '<addr> <count>'."""
    cnt = collections.Counter()
    pat_sp = re.compile(r'^\s*[\d.]+%\s+(\d+)\s+(?:0x)?([0-9a-fA-F]{8,16})\s*$')
    pat_raw = re.compile(r'^\s*(?:0x)?([0-9a-fA-F]{8,16})\s+(\d+)\s*$')
    for line in open(path, errors="replace"):
        m = pat_sp.match(line)
        if m:
            cnt[int(m.group(2), 16)] += int(m.group(1)); continue
        m = pat_raw.match(line)
        if m:
            cnt[int(m.group(1), 16)] += int(m.group(2))
    return cnt

def kaslr_offset(samples, sysmap, kallsyms):
    lo, hi = sysmap["_stext"], sysmap["_etext"]
    total = sum(samples.values())
    inside = sum(c for a, c in samples.items() if lo <= a < hi)
    if total and inside / total > 0.9:
        return 0
    if kallsyms:
        for line in open(kallsyms):
            p = line.split()
            if len(p) >= 3 and p[2] == "_text":
                return sysmap["_text"] - int(p[0], 16)
    sys.exit("samples are outside vmlinux .text and no kallsyms _text given (KASLR offset unknown)")

def symbolize(symbolizer, vmlinux, addrs):
    inp = "".join("0x%x\n" % a for a in addrs)
    out = subprocess.run([symbolizer, "--obj=" + vmlinux, "--inlining", "--output-style=JSON"],
                         input=inp, capture_output=True, text=True, check=True).stdout
    res = {}
    for line in out.splitlines():
        if not line.strip():
            continue
        j = json.loads(line)
        res[int(j["Address"], 16)] = j.get("Symbol", [])
    return res

class Node:
    __slots__ = ("lines", "calls")
    def __init__(self):
        self.lines = collections.defaultdict(int)   # "off[.disc]" -> max count
        self.calls = {}                             # ("off[.disc]", callee) -> Node
    def total(self):
        return sum(self.lines.values()) + sum(n.total() for n in self.calls.values())

def loc(frame):
    off = max(int(frame.get("Line", 0)) - int(frame.get("StartLine", 0)), 0)
    d = int(frame.get("Discriminator", 0) or 0)
    return "%d.%d" % (off, d) if d else "%d" % off

def build(samples, syms):
    funcs = {}
    for addr, c in samples.items():
        frames = [f for f in syms.get(addr, []) if f.get("FunctionName") not in (None, "", "??")]
        if not frames or int(frames[-1].get("StartLine", 0)) == 0:
            continue
        top = frames[-1]["FunctionName"]
        node = funcs.setdefault(top, Node())
        for i in range(len(frames) - 1, 0, -1):         # outermost -> innermost call sites
            key = (loc(frames[i]), frames[i - 1]["FunctionName"])
            node = node.calls.setdefault(key, Node())
        l = loc(frames[0])
        node.lines[l] = max(node.lines[l], c)          # AutoFDO: max over a line's instructions
    return funcs

def emit(fh, name, node, indent, head=None):
    tot = node.total()
    if indent == 0:
        first = min(node.lines.items(), key=lambda kv: float(kv[0]), default=(None, 0))[1]
        fh.write("%s:%d:%d\n" % (name, tot, head if head is not None else first))
    for l, c in sorted(node.lines.items(), key=lambda kv: float(kv[0])):
        fh.write("%s%s: %d\n" % (" " * (indent + 1), l, c))
    for (l, callee), sub in sorted(node.calls.items(), key=lambda kv: float(kv[0][0])):
        fh.write("%s%s: %s:%d\n" % (" " * (indent + 1), l, callee, sub.total()))
        emit(fh, callee, sub, indent + 1)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vmlinux", required=True); ap.add_argument("--sysmap", required=True)
    ap.add_argument("--report", required=True); ap.add_argument("--kallsyms")
    ap.add_argument("--symbolizer", required=True); ap.add_argument("--profdata", required=True)
    ap.add_argument("--out", required=True); ap.add_argument("--min-count", type=int, default=2)
    a = ap.parse_args()
    sysmap = read_sysmap(a.sysmap)
    samples = read_samples(a.report)
    if not samples:
        sys.exit("no samples parsed from " + a.report)
    off = kaslr_offset(samples, sysmap, a.kallsyms)
    samples = collections.Counter({addr + off: c for addr, c in samples.items()})
    lo, hi = sysmap["_stext"], sysmap["_etext"]
    samples = collections.Counter({k: v for k, v in samples.items() if lo <= k < hi})
    total = sum(samples.values())
    print("samples: %d at %d addresses (KASLR offset 0x%x)" % (total, len(samples), off & (2**64 - 1)))
    syms = symbolize(a.symbolizer, a.vmlinux, sorted(samples))
    funcs = {k: v for k, v in build(samples, syms).items() if v.total() >= a.min_count}
    txt = a.out + ".txt"
    with open(txt, "w") as fh:
        for name, node in sorted(funcs.items(), key=lambda kv: -kv[1].total()):
            emit(fh, name, node, 0)
    subprocess.run([a.profdata, "merge", "--sample", "--extbinary", txt, "-o", a.out], check=True)
    hot = sorted(funcs.items(), key=lambda kv: -kv[1].total())[:15]
    print("functions in profile: %d" % len(funcs))
    for n, node in hot:
        print("  %8d  %s" % (node.total(), n))
    print("wrote %s (text: %s)" % (a.out, txt))

if __name__ == "__main__":
    main()
