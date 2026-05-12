#!/usr/bin/env python3

from argparse import ArgumentParser
from csv import DictReader

# column name defines
TEMPLATE = "template"
SCORE = "score"
EXPECTED = "expected"
TEMPLATE_LENGTH = "template_length"
TEMPLATE_IDENTITY = "template_identity"
TEMPLATE_COVERAGE = "template_coverage"
QUERY_IDENTITY = "query_identity"
QUERY_COVERAGE = "query_coverage"
DEPTH = "depth"
Q_VAL = "q_value"
P_VAL = "p-value" # kma result header seems to use both "-" and "_"

FIELDNAMES = [TEMPLATE, SCORE, EXPECTED, TEMPLATE_LENGTH, TEMPLATE_IDENTITY, TEMPLATE_COVERAGE, QUERY_IDENTITY, QUERY_COVERAGE, DEPTH, Q_VAL, P_VAL]

def get_species_tag(header: str):
    return header.split(" ")[1]

def select_best_kma_references(kma_file: str, min_coverage: float, min_depth: float) -> list[str]:
    ret: dict[str, str] = {}

    with open(kma_file, "r") as inf:
        reader = DictReader(inf, delimiter = "\t", fieldnames = FIELDNAMES)
        rows = [row for row in reader]
        rows = rows[1:]

        if not rows:
            raise ValueError(f"KMA results file {kma_file} is empty!")

        rows.sort(key = lambda x: (float(x[SCORE]), float(x[TEMPLATE_COVERAGE]), float(x[TEMPLATE_IDENTITY]), float(x[DEPTH]), float(x[P_VAL])), reverse = True)
        for row in rows:
            if not float(row[TEMPLATE_COVERAGE]) >= min_coverage and float(row[DEPTH]) >= min_depth: continue
            if get_species_tag(row[TEMPLATE]) in ret: continue
            ret[get_species_tag(row[TEMPLATE])] = row[TEMPLATE]

        return list(ret.values())

def find_ref_in_fasta(fasta: str, ref_name: str) -> str:
    found = False
    ret = ""

    with open(fasta, "r") as inf:
        for l in inf:
            if found:
                ret += l # add sequence
                return ret

            if l.startswith(">"):
                if ref_name in l:
                    print(ref_name)
                    found = True
                    ret += ">" + get_species_tag(l) + "\n" # add header
                    continue

    raise ValueError(f"ref {ref_name} is not in the fasta file {fasta}!")


if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument("-i", required = True, help = "kma res file", type = str)
    parser.add_argument("--prefix", required = True, help = "prefix for output file", type = str)
    parser.add_argument("-r", required = True, help = "reference fasta that contains references listed in the KMA file", type = str)
    parser.add_argument("--min_coverage", required = True, help = "minimum reference coverage (percent) for a reference to be selected", type = float)
    parser.add_argument("--min_depth", required = True, help = "minimum mean depth for a reference to be selected", type = float)

    args = parser.parse_args()

    selected = select_best_kma_references(args.i, args.min_coverage, args.min_depth)

    for ref in selected:
        record = find_ref_in_fasta(args.r, ref)
        with open(f"{args.prefix}_{get_species_tag(ref)}_best_ref.fa", "w") as outf:
            outf.write(record)
