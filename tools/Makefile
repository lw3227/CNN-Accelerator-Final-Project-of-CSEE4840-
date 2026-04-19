ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /C
ifeq ($(CC),cc)
CC := gcc
endif
RM := del /Q /F
EXEEXT := .exe
else
CC ?= gcc
RM := rm -f
EXEEXT :=
endif

CFLAGS ?= -O2 -std=c11 -Wall -Wextra -I../include
LDFLAGS ?=
COMMON_OBJS := cnn_mmio_host.o
BINARIES := hps_mmio_infer$(EXEEXT) hps_mmio_status$(EXEEXT) hps_mmio_load_model$(EXEEXT) hps_mmio_run_case$(EXEEXT) hps_mmio_rw$(EXEEXT) hps_sysreg_rw$(EXEEXT)

.PHONY: all clean

all: $(BINARIES)

cnn_mmio_host.o: cnn_mmio_host.c ../include/cnn_mmio_host.h ../include/cnn_mmio_regs.h
	$(CC) $(CFLAGS) -c -o $@ cnn_mmio_host.c

hps_mmio_infer$(EXEEXT): hps_mmio_infer.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_infer.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_status$(EXEEXT): hps_mmio_status.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_status.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_load_model$(EXEEXT): hps_mmio_load_model.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_load_model.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_run_case$(EXEEXT): hps_mmio_run_case.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_run_case.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_rw$(EXEEXT): hps_mmio_rw.c ../include/cnn_mmio_regs.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_rw.c $(LDFLAGS)

hps_sysreg_rw$(EXEEXT): hps_sysreg_rw.c
	$(CC) $(CFLAGS) -o $@ hps_sysreg_rw.c $(LDFLAGS)

clean:
	-$(RM) $(COMMON_OBJS) $(BINARIES)
