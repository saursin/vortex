ROOT_DIR := $(realpath ../../..)
include $(ROOT_DIR)/config.mk

PROJECT := llama

SRC_DIR := $(VORTEX_HOME)/tests/regression/$(PROJECT)

SRCS := $(SRC_DIR)/llama.cpp $(SRC_DIR)/vxmath.cpp

VX_SRCS := $(SRC_DIR)/matmul_kernel.cpp

OPTS ?= $(SRC_DIR)/stories15M.bin -z $(SRC_DIR)/tokenizer.bin -n 40 -v 1

include ../common.mk
