
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
    ret_after_read resq 1 ; Zmienna pomocnicza do przechowywania adresu powrotu po odczycie
    ret_after_byteread resq 1 ; Zmienna pomocnicza do przechowywania adresu powrotu po odczycie bajtu
    out_buffer resq 2 ; Bufor na wypisywane dane
section .text
    global _start

; Rejestry o określonym przeznaczeniu do końca wykonywania programu:
; r8 - stopień wielomianu CRC
; Aż do przetwarzania pliku:
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
    mov [r11 + rcx*8], rax
    inc rcx
    jmp generate_lut_loop

generate_lut_end:
    mov rdi, r9
    mov rsi, open_mode
    mov rax, SYS_OPEN
    syscall
    cmp rax, 0
    jl error_exit
    mov [rel fd], rax
    ; Chcemy przejść do handle new fragment, aby domyślnie wyzerować liczniki
    ; TODO: TU DODAĆ JUMP NA ODPOWIEDNIE CZYTANIE 8 BAJTÓW NA START
    lea rax, [rel handle_read_byte_callback]
    mov [rel ret_after_byteread], rax
    ; Od teraz r10 będzie ustawione na 1 kiedy nie ma już więcej fragmentów do przetworzenia
    ; W r14 będziemy przetwarzać plik, tj. kolejne 8 bajtowe fragmenty
    xor r10, r10
    xor r12, r12
    xor r13, r13
    xor r14, r14
    xor r15, r15
    
    ; Na początek chcemy załadować pierwsze <= 8 bajtów
    mov rbx, 0x8

; W r14 będziemy trzymać przetwarzany fragment, a w r15 ilośc bajtów do przetworzenia
handle_read_byte:
    jmp read_byte
handle_read_byte_callback:
    shl r14, 0x8
    or r14, rdx
    dec rbx
    test rbx, rbx
    jnz handle_read_byte
    lea rax, [rel process_loop_callback]
    mov [rel ret_after_byteread], rax

process_loop:
    test r15, r15
    jz print_output
    jmp read_byte
process_loop_callback:
    mov rax, r14
    shr rax, 0x38
    shl r14, 0x8
    or r14, rdx
    dec r15
    lea rcx, [rel lut]
    mov rbx, [rcx + rax*8]
    xor r14, rbx
    jmp process_loop

print_output:
    xor rcx, rcx
    lea rax, [rel out_buffer]
print_output_loop:
    cmp rcx, r8
    je print_output_syscall
    shl r14, 1
    setc dl
    add dl, '0'
    mov [rax + rcx], dl
    inc rcx
    jmp print_output_loop
    
print_output_syscall:
    mov byte [rax + rcx], 0xA ; Do bufora dodajemy znak nowej linii
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [rel out_buffer]
    mov rdx, rcx
    inc rdx
    syscall
    cmp rax, 0
    jl error_exit
    jmp close_file

read_byte_handle_new_fragment:
    xor r13, r13

; O ile to możliwe, to wczyta kolejny bajt do dl, w r13 trzyma na którym bajcie we fragmencie jesteśmy, a w r15 ile przeczytano bajtów
read_byte:
    xor rdx, rdx
    cmp r12, -1
    je read_byte_finish
    lea rax, [rel read_byte_handle_new_fragment]
    mov [rel ret_after_read], rax
    cmp r12, r13
    je open_new_fragment
    lea rcx, [rel buffer]
    xor rdx, rdx
    mov dl, [rcx + r13]
    inc r15
    inc r13

read_byte_finish:
    jmp [rel ret_after_byteread]

; Jeśli chcemy otworzyć nowy fragment, a już wczytaliśmy wszystkie fragmenty, to ustawiamy długość na -1
open_new_fragment_eof:
    mov r12, -1
    jmp [rel ret_after_read]

; Na koniec umieszcza w r12 długość fragmentu w buforze, r10 ustawi na 1 jeśli nie ma więcej fragmentów po obecnym,
; dodatkowo r12 na -1 jeśli nie załadowano nowego fragmentu, bo się skończyły
open_new_fragment:
    test r10, r10
    jnz open_new_fragment_eof
    mov rdi, [rel fd]
    lea rsi, [rel fragment_length]
    mov rdx, 0x2

open_new_fragment_read:
    mov rax, SYS_READ
    syscall

    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jle error_exit_close_file
    test rdx, rdx
    jnz open_new_fragment_read

    ; W przypadku fragmentu zerowej długości od razu go przeskakujemy
    movzx rax, word [rel fragment_length]
    test rax, rax
    ; TODO: pamiętać, że wczytany fragment może być zerowej długości, wówczas czytać fragmenty do skutku 
    jz jump_to_next_fragment

    ; W przeciwnym przypadku ładujemy nowy fragment do bufora
    mov rdi, [rel fd]
    lea rsi, [rel buffer]
    movzx rdx, word [rel fragment_length]

open_new_fragment_read_into_buffer:
    mov rax, SYS_READ
    syscall

    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jle error_exit_close_file
    test rdx, rdx
    jnz open_new_fragment_read_into_buffer

jump_to_next_fragment:
    movzx rdx, word [rel fragment_length]
    mov rdi, [rel fd]
    lea rsi, [rel next_fragment_jump]
    mov rdx, 0x4

jump_to_next_fragment_read:
    mov rax, SYS_READ
    syscall
    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jle error_exit_close_file
    test rdx, rdx
    jnz jump_to_next_fragment_read

    xor rdx, rdx
    movzx rdx, word [rel fragment_length]

    movsxd rax, [rel next_fragment_jump]
    ; Sprawdzamy czy offset wskazuje na początek fragmentu
    neg rax
    ; Chcemy sprawdzić czy fragment wskazuje na samego siebie, czyli czy skok wraca na początek,
    ; a z uwagi na to, że każdy fragment zawiera 6 bajtów - długość, skok - poza treścią, to musimy je odjąć
    sub rax, 0x6
    cmp rax, rdx
    mov rax, rdx
    je handle_eof
    mov rax, SYS_LSEEK
    mov rdi, [rel fd]
    movsxd rsi, [rel next_fragment_jump]
    ;TODO: wywalić
    mov rdx, SEEK_CUR
    syscall
    cmp rax, 0
    jl error_exit_close_file

jump_to_next_fragment_finish:
    ; TODO: co robimy po odczytaniu fragmentu? poki co wiecej fragmentow
    movzx r12, word [rel fragment_length]
    jmp [rel ret_after_read]

handle_eof:
    mov r10, 1
    ; TODO: zmienić
    jmp jump_to_next_fragment_finish

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