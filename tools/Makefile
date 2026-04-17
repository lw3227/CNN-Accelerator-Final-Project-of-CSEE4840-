CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -I../include
LDFLAGS ?=
COMMON_OBJS := cnn_mmio_host.o

.PHONY: all clean

all: hps_mmio_infer hps_mmio_status hps_mmio_load_model hps_mmio_run_case

cnn_mmio_host.o: cnn_mmio_host.c ../include/cnn_mmio_host.h ../include/cnn_mmio_regs.h
	$(CC) $(CFLAGS) -c -o $@ cnn_mmio_host.c

hps_mmio_infer: hps_mmio_infer.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_infer.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_status: hps_mmio_status.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_status.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_load_model: hps_mmio_load_model.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_load_model.c $(COMMON_OBJS) $(LDFLAGS)

hps_mmio_run_case: hps_mmio_run_case.c $(COMMON_OBJS) ../include/cnn_mmio_host.h
	$(CC) $(CFLAGS) -o $@ hps_mmio_run_case.c $(COMMON_OBJS) $(LDFLAGS)

clean:
	rm -f $(COMMON_OBJS) hps_mmio_infer hps_mmio_status hps_mmio_load_model hps_mmio_run_case
