#You should be in the "vcs_sim/" directory
ROOT_DIR := $(realpath ../..)
VORTEX_HOME := $(realpath ../..)

RTL_DIR := $(HW_DIR)/rtl

FILELIST_FILE_NAME=filelist_syn.f

include $(VORTEX_HOME)/tapeout_config.mk
include $(VORTEX_HOME)/config.mk.in

SIM=1
SDF=0

#Defines statement for vcs
VERILOG_DEFINES:= 
ifeq ($(SIM),1)
		VERILOG_DEFINES := $(VERILOG_DEFINES)+define+SIM=1
endif
ifeq ($(SDF),1)
		VERILOG_DEFINES := $(VERILOG_DEFINES)+define+SDF=1
endif

VERILOG_DEFINES+= $(TAPEOUT_DEFINES)
VERILOG_DEFINES+= +define+VCS_SIM
VERILOG_DEFINES+= +define+SIMULATION
VERILOG_DEFINES+= +define+SYNTHESIS
VERILOG_DEFINES+= +define+SYNOPSYS
#Fast simulation flag for memory model
VERILOG_DEFINES += +define+UNIT_DELAY
#Disables warning messages from the memory model
VERILOG_DEFINES += +define+no_warning
#Define for debug print statements for main memory
# VERILOG_DEFINES+= +define+DEBUG_MEM

#Define to replace mem coalescer data table with compiled sram !!!NOT WORKING!!!
# VERILOG_DEFINES += +define+DTABLE_SRAM
#Define to replace cache tag store with compiled sram !!NOT WORKING!!
# VERILOG_DEFINES += +define+CACHE_TAG_STORE_SRAM
#Define to replace cache fifo store with compiled sram !!(MAYBE) WORKING!!
# VERILOG_DEFINES += +define+CACHE_FIFO_STORE_SRAM
#Define to replace cache mshr store with compiled sram !!NOT WORKING!!
# VERILOG_DEFINES += +define+CACHE_MSHR_STORE_SRAM


.DEFAULT_GOAL := run_and_view
CURRENT_DIR := $(shell pwd)
WORKSPACE = $(CURRENT_DIR)/WORKSPACE
TESTNAME :=
PROGRAM ?= program_files/conform.mem

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

# +lint=all -kdb 		-timescale=1ns/10ps -debug_acc+pp+dmptf -debug_region+cell+encrypt +incdir+sym_links +incdir+sym_links/common_cells +lint=all
# remove assert none later
#+neg_tchk
vcs: ./Include/${FILELIST_FILE_NAME} 
	cd $(WORKSPACE) && \
	vcs -file sym_links/sim_no_path.include +v2k -R -sverilog -full64 \
		-timescale=1ns/10ps -assert disable -kdb -debug_access+all -debug_acc+pp+dmptf -debug_region+cell+encrypt -l simulation.log +fsdb +fsdb+all +fsdbfile+./simulation.fsdb $(VERILOG_DEFINES) +testname=$(TESTNAME) \
		-top tb_top +program=../$(PROGRAM) +incdir+sym_links +incdir+sym_links/common_cells \
		-lca -kdb \
		+sdfverbose 
		# simv

clean:
	rm -rf WORKSPACE

