; #-----------------Opis programu-----------------#
; Poniższy program oblicza kod CRC dla pliku podanego przez nazwę w pierwszym argumencie
; i wielomianu podanego w drugim argumencie, jako ciąg zer i jedynek będących ciągiem współczynników wielomianu,
; z wyłączeniem najwyższego współczynnika, który jest zawsze równy 1
; Wynik wypisuje na standardowe wyjście
; #-----------------------------------------------#

; Mając na uwadzę czytelność kodu wszystkie stałe związane z wywołaniami systemowymi
; przechowywujemy w .data, a zmienne globalne w .bss
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

; W lut będziemy trzymać tablicę 256 elementową, w której każdy k-ty element
; będzie wynikiem zastosowania CRC do ciągu bitów BIN(k)000...0, gdzie BIN(k) to 
; k w zapisie binarnym
section .bss
    fd resq 1 ; Deskryptor pliku, z którego będziemy czytać dane
    lut resq 256
    buffer resb 65535 ; 64KB bufor na dane
    fragment_length resw 1 ; Długość obecnego fragmentu
    next_fragment_jump resd 1 ; Tu będziemy zapisywać przeskok do następnego fragmentu
    error resq 1 ; Ustawiane na 1 w przypadku błędu
    ret_after_read resq 1 ; Zmienna pomocnicza do przechowywania adresu powrotu po odczycie fragmentu
    ret_after_byteread resq 1 ; Zmienna pomocnicza do przechowywania adresu powrotu po odczycie kolejnego bajtu z pliku
    out_buffer resq 2 ; Bufor na wypisywane dane
section .text
    global _start

; #-----------Rejestry o określonym przeznaczeniu do końca wykonywania programu------------#
; r8 - stopień wielomianu CRC
; Dopóki nie zacznie się przetwarzanie pliku natsępujące rejestry mają takowe przeznaczenie:
; r10 - współczynniki wielomianu CRC domnożone przez x^k
; tak aby stopień CRC wynosił 64, bez wiodącego współczynnika
; #----------------------------------------------------------------------------------------#
_start:
    ; W rax dostaniemy ilość argumentów
    pop rax
    ; Sprawdzamy ilość argumentów
    cmp rax, 3
    jne error_exit
    ; Ignorujemy nazwę programu
    pop rax
    ; r9 - wskaźnik na nazwę pliku, o gwarancji prawidłowości aż do otworzenia pliku
    pop r9
    ; rbx - wskaźnik na ciąg bitów
    pop rbx
    ; Będziemy używać rax i rcx w pętli zamieniającej ciąg bitów na liczbę
    xor rax, rax
    xor rcx, rcx

; Pętla zamieniająca ciąg bitów na liczbę, w rax będzie wynik, tj. crc
convert_bit_string:
    ; Ładujemy do dl kolejny znak
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
    ; Zapisujemy w r8 stopień
    mov r8, rcx
    ; Odejmujemy 64 od rcx, aby upewnić się, że stopień wielomianu jest w odpowiednim zakresie
    sub rcx, 0x40
    neg rcx
    ; Wykonujemy wspomniane porównanie
    cmp rcx, 0
    jl error_exit
    ; Domnażamy nasz wielomian przez x^k tak, aby jego stopień wynosił 64
    sal rax, cl
    mov r10, rax
    ; Aby wygenerować lut tymczasowo przechowamy też CRC w rdx
    mov rdx, rax

generate_lut:
    xor rcx, rcx

; W tej pętli w rcx będziemy przechodzić przez wszystkie możliwe wartości liczby ośmiobitowej
; i liczyć dla każdej z nich kod CRC
generate_lut_loop:
    cmp rcx, 0xFF
    jg generate_lut_end
    xor rax, rax
    mov al, cl
    ; Przesuwamy nasz bajt na początek rax
    shl rax, 0x38
    ; Bl będzie iteratorem wewnętrzenej pętli generującej CRC,
    ; w której będziemy przesuwać rax w lewo i sprawdzać czy wiodący bit był jedynką
    mov bl, 0x8

generate_lut_inner_loop:
    dec bl
    test bl, bl
    jl generate_lut_loop_store
    shl rax, 1
    ; W zależności od tego czy wiodący bit był jedynką czy nie, wykonujemy XOR z wielomianem
    jnc generate_lut_inner_loop
    xor rax, rdx
    jmp generate_lut_inner_loop

; W ramach tej procedury w lut zapisujemy na odpowiednim indeksie wynik dla danej wartości
generate_lut_loop_store:
    lea r11, [rel lut]
    mov [r11 + rcx*8], rax
    inc rcx
    jmp generate_lut_loop

generate_lut_end:
    ; Otwieramy plik
    mov rdi, r9
    mov rsi, open_mode
    mov rax, SYS_OPEN
    syscall
    ; Sprawdzamy czy otwarcie się powiodło
    cmp rax, 0
    jl error_exit
    ; Zapisujemy deskryptor pliku, aby go odczytywać
    mov [rel fd], rax
    ; Będziemy teraz czytać bajt po bajcie z pliku, w związku z czym ustawiamy zmienną
    ; trzymającą adres powrotu po odczycie bajtu na naszą procedurę obsługującą odczyt
    lea rax, [rel handle_read_byte_callback]
    mov [rel ret_after_byteread], rax
    ; #--------Rejestry i ich przeznaczenie w trakcie przetwarzania pliku--------#
    ; Od teraz r10 będzie ustawione na 1 wtw., gdy nie ma już więcej fragmentów do przetworzenia
    ; W r14 będziemy przetwarzać plik, tj. ładować do niego kolejne 8 bajtowe fragmenty
    ; W r15 będziemy trzymać ilość bajtów do przetworzenia
    ; W r12 będziemy trzymać długość obecnego fragmentu
    ; W r13 będziemy trzymać na którym bajcie w fragmencie jesteśmy
    ; #--------------------------------------------------------------------------#
    xor r10, r10
    xor r12, r12
    xor r13, r13
    xor r14, r14
    xor r15, r15
    
    ; Na początek chcemy załadować pierwsze 8 bajtów 
    ; (dla plików <8 bajtowych odpowiednio zamiast brakujących bajtów załadować zera), 
    ; aby poprawnie korzystać z lut, więc wykonamy rbx=8 razy procedurę read_byte, 
    ; co załaduje pierwsze <=8 bajtów
    mov rbx, 0x8

handle_read_byte:
    jmp read_byte
handle_read_byte_callback:
    shl r14, 0x8
    ; Ładujemy do r14 bajt wczytany do rdx
    or r14, rdx
    dec rbx
    test rbx, rbx
    jnz handle_read_byte
    ; Po wczytaniu wspomnianych 8 bajtów możemy zacząć przetwarzać plik,
    ; więc zmieniamy adres powrotu po odczycie bajtu na naszą procedurę przetwarzającą plik
    lea rax, [rel process_loop_callback]
    mov [rel ret_after_byteread], rax

; W poniższej procedurze przetwarzamy nasz plik bajt po bajcie
process_loop:
    ; Gdy r15=0 przetworzyliśmy już wszystkie bajty i możemy wypisać wyjście
    test r15, r15
    jz print_output
    jmp read_byte
process_loop_callback:
    ; Ładujemy do al najbardziej znaczący bajt r14
    mov rax, r14
    shr rax, 0x38
    ; Przesuwamy r14 o bajt w lewo
    shl r14, 0x8
    ; Ładujemy nowy bajt do r14
    or r14, rdx
    dec r15
    ; Ładujemy do rbx odpowiednią wartość z lut
    lea rcx, [rel lut]
    mov rbx, [rcx + rax*8]
    ; Wykonujemy XOR na r14 i rbx, tj. obecnie przetwarzanym fragmencie i zapamiętanej wartości CRC dla bajtu,
    ; który został wysunięty z przetwarzanego fragmentu
    xor r14, rbx
    jmp process_loop

; Poniższa procedura wypisuje wynik na standardowe wyjście za pomocą systemowego wywołania SYS_WRITE,
; przy czym na początek zmienia wynik na ciąg znaków ascii
print_output:
    ; W rcx będziemy trzymać iterator pętli przetwarzającej kolejne bity wyniku,
    ; tj. zmieniającej bity wyniku na znaki ascii, 
    ; a do rax ładujemy adres naszego bufora na ciągi znaków wypisywane na standardowe wyjście
    xor rcx, rcx
    lea rax, [rel out_buffer]
print_output_loop:
    ; Sprawdzamy czy rcx jest równe stopniowi wielomianu
    cmp rcx, r8
    je print_output_syscall
    shl r14, 1
    ; Ładujemy do dl bit, który wysunęliśmy
    setc dl
    ; Zamieniamy bit na znak ascii dodając kod zera
    add dl, '0'
    mov [rax + rcx], dl
    inc rcx
    jmp print_output_loop

; Ta część naszej procedury odpowiada za wykonanie odpowiedniego wywołania systemowego
; wypisującego bufor na standardowe wyjście
print_output_syscall:
    ; Na koniec bufora dodajemy znak nowej linii, tj. 0xA
    mov byte [rax + rcx], 0xA
    ; Wywołujemy systemowe wywołanie SYS_WRITE na naszym buforze
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    lea rsi, [rel out_buffer]
    mov rdx, rcx
    inc rdx
    syscall
    cmp rax, 0
    jl error_exit
    ; Po pomyślnym wypisaniu kodu CRC możemy zakończyć program po uprzednim zamknięciu pliku
    jmp close_file

; Poniższa procedura obsługuje odczyt bajtu z pliku,
; przy czym zaczyna się od wyzerowania r13, ponieważ
; jest to rejestr przechowywujący indeks bajtu w fragmencie,
; który należy następnie przeczytać, czyli po odczycie nowego fragmentu ten rejestr
; powinien być ustawiony na zero (przy czym nasz program automatycznie pomija fragmenty zerowej długości)
read_byte_handle_new_fragment:
    xor r13, r13

; Konkretniej nasza procedura, o ile to możliwe, wczyta kolejny bajt do dl
read_byte:
    ; Przygotowywujemy rdx na wczytanie bajtu
    xor rdx, rdx
    ; Jeśli r12=-1, to wówczas nie ma więcej fragmentów do wczytania i przedwcześnie kończymy procedurę
    cmp r12, -1
    je read_byte_finish
    ; Ustawiamy adres powrotu po odczycie fragmentu na naszą procedurę obsługującą odczyt bajtu
    lea rax, [rel read_byte_handle_new_fragment]
    mov [rel ret_after_read], rax
    ; W przypadku dojścia do końca fragmentu, wczytujemy nowy fragment
    cmp r12, r13
    je open_new_fragment
    ; Następnie do rcx ładujemy adres bufora, z którego będziemy czytać
    lea rcx, [rel buffer]
    xor rdx, rdx
    ; Ostatecznie, zgodnie ze specyfikacją, wczytujemy nowy bajt do dl
    mov dl, [rcx + r13]
    ; W związku z czym następnym razem chcemy czytać kolejny bajt, z uwagi na co zwiększamy r13,
    ; i jednocześnie zwiększyła się ilość bajtów, które wczytaliśmy, więc zwiększamy r15
    inc r15
    inc r13

read_byte_finish:
    ; Wracamy do procedury, która wywołała odczyt bajtu
    jmp [rel ret_after_byteread]

; Poniższa procedura obsługuje odczyt fragmentu z pliku, załadowanie go do bufora, przeskoczenie do następnego fragmentu
; i obsługę końca pliku
;
; W poniższej podprocedurze mamy do czynienia z próbą wczytania fragmentu, po skończeniu się pliku,
; w takowym przypadku ustawiamy długość wczytanego fragmentu na -1
open_new_fragment_eof:
    mov r12, -1
    jmp [rel ret_after_read]

; Poniżej znajduje się zasadnicza część procedury,
; zgodnie ze specyfikacją umieszcza w r12 długość fragmentu w buforze, 
; r10 ustawi na 1 jeśli nie ma więcej fragmentów po obecnym,
; dodatkowo r12 będzie ustawione na -1 jeśli nie załadowano nowego fragmentu, bo się skończyły
open_new_fragment:
    ; Sprawdzamy czy jesteśmy na końcu pliku
    test r10, r10
    jnz open_new_fragment_eof
    ; Wpp. ładujemy długość fragmentu do rax przez SYS_READ
    mov rdi, [rel fd]
    lea rsi, [rel fragment_length]
    mov rdx, 0x2

open_new_fragment_read:
    mov rax, SYS_READ
    syscall

    ; Jeśli SYS_READ przeczytało mniej bajtów niż chcieliśmy, to aż do skutku - o ile nie ma błędu - czytamy z pliku
    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jle error_exit_close_file
    test rdx, rdx
    jnz open_new_fragment_read

    ; W przypadku fragmentu zerowej długości od razu go przeskakujemy bez ładowania go do bufora
    movzx rax, word [rel fragment_length]
    test rax, rax
    jz jump_to_next_fragment

    ; W przeciwnym przypadku ładujemy nowy fragment do bufora za pomocą SYS_READ
    mov rdi, [rel fd]
    lea rsi, [rel buffer]
    movzx rdx, word [rel fragment_length]

; Podprocedura ładująca fragment do bufora
open_new_fragment_read_into_buffer:
    mov rax, SYS_READ
    syscall

    ; Tak jak uprzednio czytamy aż do skutku, o ile nie ma błędu
    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jle error_exit_close_file
    test rdx, rdx
    jnz open_new_fragment_read_into_buffer

; Po wczytaniu fragmentu do bufora przeskakujemy do następnego fragmentu,
; co wykonuje poniższa podprocedura
jump_to_next_fragment:
    ; Na początek odczytujemy adres skoku do następnego fragmentu
    mov rdi, [rel fd]
    lea rsi, [rel next_fragment_jump]
    mov rdx, 0x4

; Tutaj wykonujemy wspomniane wywołanie systemowe odczytujące adres
jump_to_next_fragment_read:
    mov rax, SYS_READ
    syscall
    ; Z analogicznym czytaniem do skutku
    sub rdx, rax
    add rsi, rax
    cmp rax, 0
    jle error_exit_close_file
    test rdx, rdx
    jnz jump_to_next_fragment_read

    ; Chcąc dowiedzieć się, czy przetworzliśmy cały plik,
    ; chcemy sprawdzić czy fragment wskazuje na samego siebie, czyli czy skok wraca na początek fragmentu,
    ; czyli ponieważ fragment składa się z 6 bajtów i właściwej zawartości, 
    ; to ładujemy do rdx długość fragmentu, do rax skok
    ; i sprawdzamy czy skok jest równy długości fragmentu, czyli rozmiarowi zawartości powiększonemu o 6 bajtów
    movzx rdx, word [rel fragment_length]
    movsxd rax, [rel next_fragment_jump]
    neg rax
    sub rax, 0x6
    cmp rax, rdx
    mov rax, rdx
    je handle_eof
    ; W przeciwnym przypadku przeskakujemy do następnego fragmentu
    mov rax, SYS_LSEEK
    mov rdi, [rel fd]
    movsxd rsi, [rel next_fragment_jump]
    mov rdx, SEEK_CUR
    syscall
    cmp rax, 0
    jl error_exit_close_file

; Na koniec otwierania fragmentu zapisujemy do r12 wspomnianą długość fragmentu i skaczemy do odpowiedniego adresu
jump_to_next_fragment_finish:
    movzx r12, word [rel fragment_length]
    jmp [rel ret_after_read]

; W przypadku przetworzenia wszystkich fragmentów, zgodnie ze specyfikacją, ładujemy do r10 jedynkę i kończymy procedurę
; skoku do następnego fragmentu
handle_eof:
    mov r10, 1
    jmp jump_to_next_fragment_finish

; Poniższa procedura zamyka plik i kończy program z kodem błędu 1
error_exit_close_file:
    mov qword [rel error], 1

; Poniższa procedura zamyka plik i kończy program z kodem jaki znajduje się w [rel error]
close_file:
    mov rdi, [rel fd]
    mov rax, SYS_CLOSE
    syscall
    cmp rax, 0
    jl error_exit

; Poniższa procedura robi to samo, co powyższa, ale z pomnięciem zamknięcia pliku
exit:
    mov rax, SYS_EXIT
    mov rdi, [rel error]
    syscall

; Etykieta służąca do natychmiastowego wyjścia z programu z kodem błędu 1
error_exit:
    mov qword [rel error], 1
    jmp exit