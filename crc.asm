%include "macro_print.asm"
; USUNAC POWYZSZE

SYS_WRITE equ 1
SYS_EXIT  equ 60
STDOUT    equ 1

; Będziemy trzymać tablicę 256 elementową, gdzie każdy k-ty element
; będzie wynikiem zastosowania CRC do ciągu bitów BIN(k)000...0, gdzie BIN(k) to 
; k w zapisie binarnym
section .bss
    lut resq 256
    buffer resb 65535 ; 64KB bufor na dane
section .text
    global _start

; Rejestry:
; r9 - wskaźnik na nazwę pliku
; r8 - stopień wielomianu CRC
; rdx - współczynniki wielomianu CRC domnożone przez x^k
; tak aby stopień CRC wynosił 64, bez wiodącego współczynnika
_start:
    pop rax
    ; Sprawdzamy ilość argumentów
    cmp rax, 3
    jne error_exit
    pop rax
    pop r9
    ; rbx - wskaźnik na ciąg bitów
    pop rbx
    xor rax, rax
    xor rcx, rcx
    print "rbx = ", rbx 

convert_bit_string:
    mov dl, [rbx + rcx]
    ; Sprawdzamy czy znak jest znakiem końca ciągu
    test dl, dl
    jz after_parsing
    ; Sprawdzamy czy znak jest postaci '0' lub '1'
    cmp dl, '0'
    jl error_exit
    cmp dl, '1'
    jg error_exit
    ; Konwertujemy znak na liczbę
    sub dl, '0'
    shl rax, 1
    or rax, rdx
    inc rcx
    jmp convert_bit_string

after_parsing:
    mov r8, rcx
    sub rcx, 0x40
    neg rcx
    ; Sprawdzamy czy ciąg bitów ma odpowiednią długość
    cmp rcx, 0
    jl error_exit
    sal rax, cl
    mov rdx, rax
    print "rbx = ", rbx 
    print "rdx = ", rdx
    print_binary rdx
    print "r8 = ", r8
    print "r9 = ", r9

generate_lut:
    xor rcx, rcx

generate_lut_loop:
    cmp rcx, 0xFF
    jg generate_lut_end
    xor rax, rax
    mov al, cl
    shl rax, 0x38
    mov bl, 0x8

generate_lut_inner_loop:
    dec bl
    test bl, bl
    jl generate_lut_loop_store
    shl rax, 1
    jnc generate_lut_inner_loop
    xor rax, rdx
    jmp generate_lut_inner_loop

generate_lut_loop_store:
    lea r11, [rel lut]
    print "after our calculations rax = ", rax
    print_binary rax
    mov [r11 + rcx*8], rax
    inc rcx
    jmp generate_lut_loop

generate_lut_end:
    PRINT_BUFFER_QWORDS 2048, lut

error_exit:
    mov rax, SYS_EXIT
    xor rdi, rdi
    inc rdi
    syscall