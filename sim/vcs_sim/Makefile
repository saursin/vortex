#You should be in the "vcs_sim/" directory
ROOT_DIR := $(realpath ../..)
VORTEX_HOME := $(realpath ../..)

RTL_DIR := $(HW_DIR)/rtl

#Defines common w/ syn
include $(VORTEX_HOME)/tapeout_config.mk
include $(VORTEX_HOME)/config.mk.in

#INCLUDE_FILE_NAME=include.f
FILELIST_FILE_NAME=filelist.f

#Defines statement for vcs
VERILOG_DEFINES:= +define+SIM=1
VERILOG_DEFINES+= +define+FPU_FPNEW
VERILOG_DEFINES+= +define+VCS_SIM
VERILOG_DEFINES+= +define+MEM_DEBUG
# VERILOG_DEFINES+= +define+SIMULATION
VERILOG_DEFINES+= $(TAPEOUT_DEFINES)

# VERILOG_DEFINES+= +define+NUM_CLUSTERS=1
# VERILOG_DEFINES+= +define+NUM_CORES=4
# VERILOG_DEFINES+= +define+NUM_WARPS=4
# VERILOG_DEFINES+= +define+NUM_THREADS=8
# VERILOG_DEFINES+= +define+FPU_FPNEW
# VERILOG_DEFINES+= +define+L1_DISABLE
# VERILOG_DEFINES+= +define+LMEM_DISABLE

.DEFAULT_GOAL := run_and_view
CURRENT_DIR := $(shell pwd)
WORKSPACE_NAME ?= WORKSPACE
WORKSPACE := $(CURRENT_DIR)/$(WORKSPACE_NAME)
TESTNAME :=
PROGRAM ?= program_files/fibonacci.mem

#INCLUDE_DIRS :=
help:
	@echo "----------------------------------------------------------------"
	@echo "Administrative targets:"
	@echo "  help           - lists make options"
	@echo "  clean          - removes the temporary files created by sim"
	@echo
	@echo "Compilation targets:"
	@echo "  link          - creates symbolic links between src and sim"
	@echo "                 folders for files listed in <design>.include"
	@echo "  vcs           - compiles code and runs simulation using vcs."
	@echo "                  make sure to run make link first"
	@echo
	@echo "Viewing targets:"
	@echo "  dve           - runs DVE to view waveforms from simulation"
	@echo "  run_and_view  - combo of make vcs and make dve"
	@echo "  verdi         - runs Verdi to view waveforms from simulation"
	@echo "  coverage      - runs Verdi to view coverage report"
	@echo 
	@echo "----------------------------------------------------------------"

link:
	if [ ! -d "$(WORKSPACE)" ]; then \
		mkdir $(WORKSPACE); \
	else \
		cd $(WORKSPACE); \
	fi
	rm -f $(WORKSPACE)/sym_links/*.sv* $(WORKSPACE)/sym_links/*.svh* $(WORKSPACE)/sym_links/*.vh*
	python3.12 link_files.py ${FILELIST_FILE_NAME}

run_and_view:
	make vcs
	make dve

dve:
	cd $(WORKSPACE) && \
	dve -full64 -vpd simulation.vpd&

verdi:
	cd $(WORKSPACE) && \
	verdi -sv -simBin ./simv \
	      -dbdir ./simv.daidir \
    	  -ssf ./simulation.fsdb &

coverage:
	cd $(WORKSPACE) && \
	verdi -cov -covdir simv.vdb&

# +lint=all -kdb 		-timescale=1ns/10ps -debug_acc+pp+dmptf -debug_region+cell+encrypt 
# remove assert none later
vcs: ./Include/${FILELIST_FILE_NAME} #./Include/${INCLUDE_FILE_NAME} 
	cd $(WORKSPACE) && \
	vcs -file sym_links/sim_no_path.include +v2k -R -sverilog -full64 -timescale=1ns/10ps -assert disable -kdb\
	    -debug_access+all -l simulation.log +fsdb +fsdb+all +fsdbfile+./simulation.fsdb $(VERILOG_DEFINES) +testname=$(TESTNAME) \
		+incdir+sym_links +incdir+sym_links/common_cells +incdir+/home/sathe/usr/jbeiler/vortex_tapeout/vortex/hw/syn/synopsys_65/build_Vortex/src -top tb_top +program=../$(PROGRAM) \
		+incdir+/home/sathe/usr/jbeiler/vortex_tapeout/vortex/third_party/cvfpu/src/common_cells/include \
		+incdir+/home/sathe/usr/jbeiler/vortex_tapeout/vortex/third_party/cvfpu/src/common_cells/src \
		+incdir+/home/sathe/usr/jbeiler/vortex_tapeout/vortex/third_party/cvfpu/src/fpu_div_sqrt_mvp/hdl \
		+incdir+/home/sathe/usr/jbeiler/vortex_tapeout/vortex/third_party/cvfpu/src
		# simv 

clean:
	rm -rf $(WORKSPACE)

