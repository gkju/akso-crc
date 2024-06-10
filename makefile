.PHONY: all clean

crc.o:
	nasm -f elf64 -w+all -w+error -o crc.o crc.asm

crc: crc.o
	ld --fatal-warnings -o crc crc.o

all: crc crc.o
clean: 
	rm -f crc crc.o