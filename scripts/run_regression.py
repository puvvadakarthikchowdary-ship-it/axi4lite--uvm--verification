#!/usr/bin/env python3
"""
AXI4-Lite UVM Regression Runner
Runs multiple seeds, parses coverage, reports pass/fail summary.
"""

import subprocess
import re

SEEDS = [1, 7, 42, 99, 2026]
TEST  = "axi4lite_regression_test"

def run_sim(seed):
    cmd = f"xrun -f sim/run.f +ntb_random_seed={seed}"
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.returncode == 0, r.stdout

def parse_cov(log):
    m = re.search(r"Functional coverage\s*=\s*([\d.]+)%", log)
    return float(m.group(1)) if m else 0.0

def main():
    total_pass = 0
    total_fail = 0
    covs = []

    for seed in SEEDS:
        print(f"Running seed={seed}...")
        ok, log = run_sim(seed)
        if ok:
            total_pass += 1
            cov = parse_cov(log)
            covs.append(cov)
            print(f"  PASS  coverage={cov:.2f}%")
        else:
            total_fail += 1
            print("  FAIL")

    print("\n=== REGRESSION SUMMARY ===")
    print(f"PASS = {total_pass}")
    print(f"FAIL = {total_fail}")
    if covs:
        print(f"Avg coverage = {sum(covs)/len(covs):.2f}%")

if __name__ == "__main__":
    main()
