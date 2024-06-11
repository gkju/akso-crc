%include "macro_print.asm"
; USUNAC POWYZSZE

section .data:
    SYS_READ equ 0
    SYS_WRITE equ 1
    SYS_OPEN equ 2
    SYS_CLOSE equ 3
    SYS_LSEEK equ 8
    SYS_EXIT  equ 60
    SEEK_CUR equ 1
    STDOUT    equ 1
    open_mode equ 0

; Będziemy trzymać tablicę 256 elementową, gdzie każdy k-ty element
; będzie wynikiem zastosowania CRC do ciągu bitów BIN(k)000...0, gdzie BIN(k) to 
; k w zapisie binarnym
section .bss
    fd resq 1 ; Deskryptor pliku, z którego będziemy czytać dane
    lut resq 256
    buffer resb 65535 ; 64KB bufor na dane
    fragment_length resw 1 ; Długość obecnego fragmentu
    next_fragment_jump resd 1 ; Tu będziemy zapisywać przeskok do następnego fragmentu
    error resq 1 ; Ustawiane na 1 w przypadku błędu
    eof resq 1 ; Ustawiane na 1 w przypadku końca pliku
section .text
    global _start

; Rejestry o określonym przeznaczeniu do końca wykonywania programu:
; r8 - stopień wielomianu CRC
; r10 - współczynniki wielomianu CRC domnożone przez x^k
; tak aby stopień CRC wynosił 64, bez wiodącego współczynnika
_start:
    pop rax
    ; Sprawdzamy ilość argumentów
    cmp rax, 3
    jne error_exit
    pop rax
    ; r9 - wskaźnik na nazwę pliku, o gwarancji prawidłowości aż do otworzenia pliku
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
    mov r10, rax
    ; Aby wygenerować lut tymczasowo przechowamy też CRC w rdx
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
    mov rdi, r9
    mov rsi, open_mode
    mov rax, SYS_OPEN
    syscall
    cmp rax, 0
    jl error_exit
    mov [rel fd], rax
    ; TODO: TU DODAĆ JUMP NA ODPOWIEDNIE CZYTANIE 8 BAJTÓW NA START
    jmp open_new_fragment

open_new_fragment:
    mov rdi, [rel fd]
    lea rsi, [rel fragment_length]
    mov rdx, 0x2

open_new_fragment_read:
    mov rax, SYS_READ
    syscall

    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jl error_exit_close_file
    test rdx, rdx
    jnz open_new_fragment_read

    ; W przypadku fragmentu zerowej długości od razu go przeskakujemy
    movzx rax, word [rel fragment_length]
    print "fragment_length = ", rax
    test rax, rax
    ; TODO: pamiętać, że wczytany fragment może być zerowej długości, wówczas czytać fragmenty do skutku 
    jz jump_to_next_fragment

    ; W przeciwnym przypadku ładujemy nowy fragment do bufora
    mov rdi, [rel fd]
    lea rsi, [rel buffer]
    movzx rdx, word [rel fragment_length]
    print "reading into buffer fragment_length = ", rdx

open_new_fragment_read_into_buffer:
    mov rax, SYS_READ
    syscall

    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jl error_exit_close_file
    test rdx, rdx
    jnz open_new_fragment_read_into_buffer

jump_to_next_fragment:
    movzx rdx, word [rel fragment_length]
    print "now we have fragment_length = ", rdx
    mov rdi, [rel fd]
    lea rsi, [rel next_fragment_jump]
    mov rdx, 0x4

jump_to_next_fragment_read:
    mov rax, SYS_READ
    syscall
    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jl error_exit_close_file
    test rdx, rdx
    jnz jump_to_next_fragment_read

    xor rdx, rdx
    movzx rdx, word [rel fragment_length]
    print "now we have fragment_length = ", rdx

    movsxd rax, [rel next_fragment_jump]
    ; Sprawdzamy czy offset wskazuje na początek fragmentu
    neg rax
    ; Chcemy sprawdzić czy fragment wskazuje na samego siebie, czyli czy skok wraca na początek,
    ; a z uwagi na to, że każdy fragment zawiera 6 bajtów - długość, skok - poza treścią, to musimy je odjąć
    sub rax, 0x6
    print " rax = ", rax
    cmp rax, rdx
    mov rax, rdx
    print " fragment_length = ", rax
    je handle_eof
    mov rax, SYS_LSEEK
    mov rdi, [rel fd]
    movsxd rsi, [rel next_fragment_jump]
    ;TODO: wywalić
    print "jumping to next_fragment_jump = ", rsi
    mov rdx, SEEK_CUR
    syscall
    cmp rax, 0
    jl error_exit_close_file

    ; TODO: co robimy po odczytaniu fragmentu? poki co wiecej fragmentow
    jmp open_new_fragment

handle_eof:
    mov qword [rel eof], 1
    ; TODO: zmienić
    print "EOF, rax = ", rax
    jmp exit

error_exit_close_file:
    mov qword [rel error], 1

close_file:
    mov rdi, [rel fd]
    mov rax, SYS_CLOSE
    syscall
    cmp rax, 0
    jl error_exit

exit:
    mov rax, SYS_EXIT
    mov rdi, [rel error]
    syscall

; Etykieta służąca do natychmiastowego wyjścia z programu z kodem błędu 1
error_exit:
    mov qword [rel error], 1
    jmp exit