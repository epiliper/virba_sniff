#!/usr/bin/env python3

import os
import argparse
import itertools

def find_pairs(files):
    ret = {}
    files.sort()

    for (f1, f2) in itertools.batched(files, 2):
        delim = "_" if "_" in f1 else "."
        d1 = d2 = 0
        paired = False
        if len(f1) == len(f2):
            d1, d2 = f1.rfind(delim), f2.rfind(delim)
            if d1 == d2 and d1 != -1:
                for i, (c1, c2) in enumerate(zip(f1, f2)):
                    if c1 != c2:
                        if c1 in ["1", "2"] and c2 in ["1", "2"] and i > d1:
                            paired = True
                            i = d1
                            break
        if not paired:
            sample_f1 = f1.split(".fastq")[0]
            sample_f2 = f2.split(".fastq")[0]
            ret[sample_f1] = [f1]
            ret[sample_f2] = [f2]

        else:
            sample = f1[0: d1]
            ret[sample] = [f1, f2]

    return ret

def make_fastq_map(dir):
    files = [f for f in os.listdir(dir) if f.endswith(".fastq") or f.endswith(".fastq.gz")]

    paired_files = find_pairs(files)
    return paired_files

def make_samplesheet(dir, samplesheet_name = "samplesheet.csv", sep = ","):
    dir = os.path.abspath(dir)
    fastq_map = make_fastq_map(dir)

    if sep == "," and not samplesheet_name.endswith(".csv"):
        samplesheet_name += ".csv"

    if sep == "\t" and not samplesheet_name.endswith(".tsv"):
        samplesheet_name += ".tsv"

    with open(samplesheet_name, "w") as outf:
        header = ["sample", "fastq_1", "fastq_2"]
        _ = outf.write(sep.join(header) + "\n")
        for sample, fastqs in fastq_map.items():
            fastqs = [os.path.join(dir, fastq) for fastq in fastqs]
            _ = outf.write(f"{sample}{sep}{sep.join(fastqs)}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input_dir", required=True, help = "input directory to make samplesheet")
    args = parser.parse_args()

    make_samplesheet(args.input_dir, "samplesheet.csv")



