# =============================
# Testbench Workbench Setup (bash/zsh)
# Usage: source setup.sh
# =============================

# Assume you are sourcing from the repo root
export TB_ROOT="$(pwd)"

# Common paths
export TB_DESIGN="$TB_ROOT/design"
export TB_DOC="$TB_ROOT/doc"
export TB_SCRATCH="$TB_ROOT/scratch"
export TB_SCRIPT="$TB_ROOT/script"
export TB_SIM="$TB_ROOT/sim"
export TB_SIMLOG="$TB_ROOT/simlog"
export TB_TB="$TB_ROOT/tb"

# Add scripts to PATH
export PATH="$TB_SCRIPT:$PATH"

# ---- cd helpers (functions) ----
go_root()    { cd "$TB_ROOT"    && pwd; }
go_design()  { cd "$TB_DESIGN"  && pwd; }
go_doc()     { cd "$TB_DOC"     && pwd; }
go_scratch() { cd "$TB_SCRATCH" && pwd; }
go_script()  { cd "$TB_SCRIPT"  && pwd; }
go_sim()     { cd "$TB_SIM"     && pwd; }
go_simlog()  { cd "$TB_SIMLOG"  && pwd; }
go_tb()      { cd "$TB_TB"      && pwd; }

go_tb_agents()  { cd "$TB_TB/agents"   && pwd; }
go_tb_defines() { cd "$TB_TB/defines"  && pwd; }
go_tb_env()     { cd "$TB_TB/env"      && pwd; }
go_tb_seq()     { cd "$TB_TB/seq_lib"  && pwd; }
go_tb_top()     { cd "$TB_TB/tb_top"   && pwd; }
go_tb_tests()   { cd "$TB_TB/tests"    && pwd; }

tbenv() {
  echo "TB_ROOT     = $TB_ROOT"
  echo "TB_DESIGN   = $TB_DESIGN"
  echo "TB_DOC      = $TB_DOC"
  echo "TB_SCRATCH  = $TB_SCRATCH"
  echo "TB_SCRIPT   = $TB_SCRIPT"
  echo "TB_SIM      = $TB_SIM"
  echo "TB_SIMLOG   = $TB_SIMLOG"
  echo "TB_TB       = $TB_TB"
}

echo "[setup.sh] Workbench ready. Try: go_tb, go_sim, go_script, tbenv"
