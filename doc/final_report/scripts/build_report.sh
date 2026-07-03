#!/usr/bin/env bash
set -euo pipefail

repo_root=$(pwd)
out_dir="doc/final_report/build"
final_pdf="doc/Precision_Dot_Product_DV_Lab_Final_Report.pdf"

mkdir -p "$out_dir"
latexmk -lualatex -interaction=nonstopmode -halt-on-error \
  -outdir="$out_dir" \
  -jobname=Precision_Dot_Product_DV_Lab_Final_Report \
  doc/final_report/final_report.tex

cp "$out_dir/Precision_Dot_Product_DV_Lab_Final_Report.pdf" "$repo_root/$final_pdf"
echo "$final_pdf"
