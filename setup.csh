# =============================
# Testbench Workbench Setup (bash/zsh)
# Usage: source setup.sh
# =============================

# Assume you are sourcing from the repo root
export RF_TOP="$(pwd)"

# Common paths
export RF_DESIGN="$RF_TOP/design"
export RF_DOC="$RF_TOP/doc"
export RF_SCRATCH="$RF_TOP/scratch"
export RF_SCRIPT="$RF_TOP/script"
export RF_SIM="$RF_TOP/sim"
export RF_SIMLOG="$RF_TOP/simlog"
export RF_TB="$RF_TOP/tb"

# Add scripts to PATH
export PATH="$RF_SCRIPT:$PATH"

# ---- cd helpers (functions) ----
go_root()    { cd "$RF_TOP"    && pwd; }
go_design()  { cd "$RF_DESIGN"  && pwd; }
go_doc()     { cd "$RF_DOC"     && pwd; }
go_scratch() { cd "$RF_SCRATCH" && pwd; }
go_script()  { cd "$RF_SCRIPT"  && pwd; }
go_sim()     { cd "$RF_SIM"     && pwd; }
go_simlog()  { cd "$RF_SIMLOG"  && pwd; }
go_tb()      { cd "$RF_TB"      && pwd; }

go_tb_agents()  { cd "$RF_TB/agents"   && pwd; }
go_tb_defines() { cd "$RF_TB/defines"  && pwd; }
go_tb_env()     { cd "$RF_TB/env"      && pwd; }
go_tb_seq()     { cd "$RF_TB/seq_lib"  && pwd; }
go_tb_top()     { cd "$RF_TB/tb_top"   && pwd; }
go_tb_tests()   { cd "$RF_TB/tests"    && pwd; }

tbenv() {
  echo "RF_TOP     = $RF_TOP"
  echo "TB_DESIGN   = $RF_DESIGN"
  echo "TB_DOC      = $RF_DOC"
  echo "TB_SCRATCH  = $RF_SCRATCH"
  echo "TB_SCRIPT   = $RF_SCRIPT"
  echo "TB_SIM      = $RF_SIM"
  echo "TB_SIMLOG   = $RF_SIMLOG"
  echo "TB_TB       = $RF_TB"
}

echo "[setup.sh] Workbench ready. Try: go_tb, go_sim, go_script, tbenv"
