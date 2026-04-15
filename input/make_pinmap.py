#!/bin/python3
# Automate making the pins.io file, useful for big buses 

f = open("./pins.io.auto", "w")


f.write("(globals\n")
f.write("\tversion = 3\n")
f.write("\tio_order = default\n")
f.write(")\n")
f.write("(iopin\n")

# Top
f.write("\t(top\n")
f.write("\t\t(pin name=\"slow_control[0]\"\t\t\toffset=26.0000 layer=4 width=0.1000 depth=0.5200 place_status=fixed)\n")
for i in range(255):
	f.write("\t\t(pin name=\"slow_control[" + str(i+1) + "]\"\t\t\tskip=0.70 layer=4 width=0.1000 depth=0.5200 place_status=fixed)\n")

f.write("\t)\n")

# Bottom
f.write("\t(bottom\n")
f.write("\t)\n")

# Left
f.write("\t(left\n")
f.write("\t\t(pin name=\"SCLK\"\t\t\toffset=26.0000 layer=4 width=0.1000 depth=0.5200 place_status=fixed)\n")
f.write("\t\t(pin name=\"DI\"\t\t\tskip=10.0 layer=4 width=0.1000 depth=0.5200 place_status=fixed)\n")
f.write("\t\t(pin name=\"CS_activelow\"\t\t\tskip=10.0 layer=4 width=0.1000 depth=0.5200 place_status=fixed)\n")
f.write("\t\t(pin name=\"DO\"\t\t\tskip=10.0 layer=4 width=0.1000 depth=0.5200 place_status=fixed)\n")
f.write("\t)\n")

# Right
f.write("\t(right\n")
f.write("\t)\n")


f.write(")\n")
f.close()
