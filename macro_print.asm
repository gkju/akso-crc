%ifndef MACRO_PRINT_ASM
%define MACRO_PRINT_ASM

; Nie definiujemy tu żadnych stałych, żeby nie było konfliktu ze stałymi
; zdefiniowanymi w pliku włączającym ten plik.

; Wypisuje napis podany jako pierwszy argument, a potem szesnastkowo zawartość
; rejestru podanego jako drugi argument i kończy znakiem nowej linii.
; Nie modyfikuje zawartości żadnego rejestru ogólnego przeznaczenia ani rejestru
; znaczników.
%macro print 2
  jmp     %%begin
%%descr: db %1
%%begin:
  push    %2                      ; Wartość do wypisania będzie na stosie. To działa również dla %2 = rsp.
  lea     rsp, [rsp - 16]         ; Zrób miejsce na stosie na bufor. Nie modyfikuj znaczników.
  pushf
  push    rax
  push    rcx
  push    rdx
  push    rsi
  push    rdi
  push    r11


  mov     eax, 1                  ; SYS_WRITE
  mov     edi, eax                ; STDOUT
  lea     rsi, [rel %%descr]      ; Napis jest w sekcji .text.
  mov     edx, %%begin - %%descr  ; To jest długość napisu.
  syscall

  mov     rdx, [rsp + 72]         ; To jest wartość do wypisania.
  mov     ecx, 16                 ; Pętla loop ma być wykonana 16 razy.
%%next_digit:
  mov     al, dl
  and     al, 0Fh                 ; Pozostaw w al tylko jedną cyfrę.
  cmp     al, 9
  jbe     %%is_decimal_digit      ; Skocz, gdy 0 <= al <= 9.
  add     al, 'A' - 10 - '0'      ; Wykona się, gdy 10 <= al <= 15.
%%is_decimal_digit:
  add     al, '0'                 ; Wartość '0' to kod ASCII zera.
  mov     [rsp + rcx + 55], al    ; W al jest kod ASCII cyfry szesnastkowej.
  shr     rdx, 4                  ; Przesuń rdx w prawo o jedną cyfrę.
  loop    %%next_digit

  mov     [rsp + 72], byte `\n`   ; Zakończ znakiem nowej linii. Intencjonalnie
                                  ; nadpisuje na stosie niepotrzebną już wartość.

  mov     eax, 1                  ; SYS_WRITE
  mov     edi, eax                ; STDOUT
  lea     rsi, [rsp + 56]         ; Bufor z napisem jest na stosie.
  mov     edx, 17                 ; Napis ma 17 znaków.
  syscall

  pop     r11
  pop     rdi
  pop     rsi
  pop     rdx
  pop     rcx
  pop     rax
  popf
  lea     rsp, [rsp + 24]
%endmacro

%macro print_binary 1
  ; Preserve registers that will be modified
  push    rax
  push    rdi
  push    rsi
  push    rdx
  push    rcx
  push    rbx
  push r8
  push rcx
  push r11
  pushf                           ; Preserve flags

  mov     rbx, %1                 ; Move the register to print into rbx for manipulation
  mov     r8, 64                 ; There are 64 bits to print in a 64-bit register

%%print_loop:
  shl     rbx, 1                  ; Shift left to get the MSB in the carry flag
  mov rcx, rbx
  setc    cl                      ; Set BL to 1 if carry flag is set, else 0
  or      cl, '0'                 ; Convert 0/1 to ASCII '0'/'1'
  mov     [rsp-1], cl             ; Store the character just above the preserved registers

  ; Setup for sys_write to print the character
  mov     rax, 1                  ; syscall number for sys_write
  mov     rdi, 1                  ; file descriptor 1 for stdout
  lea     rsi, [rsp-1]            ; pointer to the character to print
  mov     rdx, 1                  ; number of bytes to write
  syscall                         ; perform the syscall

  dec     r8                  ; Decrement the bit counter
  test r8, r8                ; Check if we're done
  jnz     %%print_loop              ; If not done, loop back

  ; Restore preserved registers
  popf
  pop r11
  pop rcx
  pop r8
  pop     rbx
  pop     rcx
  pop     rdx
  pop     rsi
  pop     rdi
  pop     rax
%endmacro

%macro PRINT_BUFFER_QWORDS 2
; Preserve registers that will be modified
  push    rax
  push    rdi
  push    rsi
  push    rdx
  push    rcx
  push    rbx
  push r8
  push rcx
  push r11
  pushf     

  ; Calculate the end of the buffer based on its size
  mov rdi, %2          ; Start of the buffer
  mov rsi, rdi
  add rsi, %1              ; End of the buffer (start + size)
  xor rdx, rdx

%%print_next_qword:
  cmp rdi, rsi             ; Compare current position with end
  jge %%print_done           ; If we've reached the end, we're done

  ; Print the index of the current QWORD
  mov rax, rdx
  print " it = ", rax        ; Assuming print_number is a macro/function that prints

  ; Print the current QWORD in binary
  mov rax, [rdi]           ; Load the current QWORD into RAX
  print_binary rax        ; Call the print_binary macro/function

  add rdi, 8               ; Move to the next QWORD
  inc rdx                  ; Increment the index
  jmp %%print_next_qword     ; Loop

%%print_done:
; Restore preserved registers
  popf
  pop r11
  pop rcx
  pop r8
  pop     rbx
  pop     rcx
  pop     rdx
  pop     rsi
  pop     rdi
  pop     rax
%endmacro

%endif
