################################################################################
# TAPEOUT Configuration
CONFIGS += -DNUM_CLUSTERS=1 -DNUM_CORES=4 -DNUM_WARPS=4 -DNUM_THREADS=8 
CONFIGS += -DFPU_FPNEW
CONFIGS += -DL1_DISABLE -DLMEM_DISABLE		# Temporary disable L1 and LMEM

TAPEOUT_DEFINES += +define+NUM_CLUSTERS=1  +define+NUM_CORES=4 +define+NUM_WARPS=4 +define+NUM_THREADS=8
TAPEOUT_DEFINES += +define+FPU_FPNEW +define+STACK_LOG2_SIZE=12
$(info =================================================================)
$(info *** USING TAPEOUT CONFIG*** (from: VORTEX_HOME/tapeout_config.mk))
$(info =================================================================)
################################################################################