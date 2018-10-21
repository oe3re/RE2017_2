;// Projekat iz Računarske elektronike
;// Studenti: Kristina Dolovac 304/2011 i Marko Lazovic 
;// Elektrotehnički fakultet u Beogradu
;// jun 2017
;// Projekat broj 2: Skaliranje slike primenom metoda najblizeg suseda

INCLUDE Irvine32.inc
INCLUDE macros.inc

.const
	BUFFER_SIZE = 200000
	MAX_PICTURE_SIZE = 65536

.data
	buffer BYTE BUFFER_SIZE DUP(?)
	filename    BYTE 80 DUP(0)
	fileHandle  HANDLE ?

	outbuffer BYTE BUFFER_SIZE DUP(?)
	outfilename BYTE 80 DUP(0)
	outfileHandle HANDLE ?
	outindex DWORD 0

	; Osnovni parametri slike:
	P2 WORD 5032h
	velicinaBafera DWORD ?
	krajBuffera DWORD ?
	N WORD ?
	M WORD ?
	Lmax WORD ?

	s word ?
	
	newM word ?
	newN word ?
	
	x0 word ?
	y0 word ?
	xr word ?
	yr word ?
	x_prim word ?
	y_prim word ?
	indexIn word ?
	duzina word ?

	pocetakNiza DWORD 0; Promenljivu koristimo kao index.
	ulazniPixeli WORD MAX_PICTURE_SIZE dup (?)
	izlazniPixeli WORD MAX_PICTURE_SIZE DUP(?); Niz koji koristimo za smestanje vrednosti iz buffera. Kada naidjemo na EOL,
																	 ; u niz upisujemo vrednost -1, zbog toga je niz tipa WORD.
																	 ; U suprotnom, ako bismo imali BYTE, vrednost -1 bila bi ista kao vrednost 255.
	broj BYTE 4 DUP(?)
	cifra WORD 0; Odredjuje da li je broj jednocif,dvocif ili trocif (WORD zbog cx).
	brojac WORD 0
	
	STOTINA WORD 100
	DESETICA WORD 10
	zaNoviRed WORD 70

.code

	close_file PROC
		mov	eax,fileHandle
		call CloseFile
		exit
	close_file ENDP
	
	;										CitajBroj
	; Pretvara vrednost ciji je pocetni clan buffer[pocetakNiza] u INT.
	; Po izlasku iz procedure vrednost je sacuvana u EAX, dok buffer[pocetakNiza] pokazuje na 20h(space).

	CitajBroj PROC STDCALL USES ebx esi ecx

		mov edx,OFFSET buffer;
		xor eax,eax
		xor ecx,ecx
		xor ebx,ebx

		add edx,pocetakNiza
		; Petlja ce se obradjivati sve dok ne naidjemo na 20h(space) ili 0Ah(EOL).
	Ucitavanje:
		mov al,[edx]
		mov broj[ebx],al
		inc edx
		inc pocetakNiza
		inc ebx
		cmp edx, krajBuffera
		je Pretvaranje
		mov al,[edx]
		cmp al,20h
		je Pretvaranje
		cmp al,0ah
		jne Ucitavanje

	Pretvaranje:
		mov broj[ebx],3 ; Kraj stringa u ASCII je 3h.
						; Ovim resavamo problem jednocifrenih i dvocifrenih brojeva.

	; ParseDecimal zahteva da EDX i ECX budu popunjeni na ovaj nacin.
		mov edx,OFFSET broj
		mov ecx,ebx
		call ParseDecimal32

	; Pre povratka iz rutine vracamo offset buffer-a u EDX.
		mov edx,OFFSET buffer
		ret
		CitajBroj ENDP


;										Uvod
; Otvaramo sliku i formiramo izlaznu sliku uz provere ispravnosti.
; Ucitavamo parametre M,N,Lmax i komentar.
; Prepisujemo prva cetiri reda u outbuffer.
; Po izlasku iz procedure vrednost buffer[pocetakNiza] pokazuje na prvi pixel,
; dok outindex pokazuje na index outbuffer-a od kojeg upisujemo promenjene pixele u proceduri IzlazniFajl.

	Uvod PROC
		mov edx, OFFSET buffer
		xor ebx,ebx
		mov ebx,edx
		add ebx,pocetakNiza
		mov ah,[ebx]
		inc ebx
		mov al,[ebx]
		cmp ax,P2
		je DrugiRed
		mWrite <"Format slike je pogresan.">
		call WriteWindowsMsg
		call close_file

	DrugiRed:
		add pocetakNiza,3  ; Sada pocetakNiza pokazuje na #.
		add ebx,2
		; Prelazimo preko komentara.
	Komentar:
		inc pocetakNiza
		inc ebx
		mov dl,[ebx]
		cmp dl,0ah
		jne Komentar

	TreciRed:  ; Labela resava problem za nesting!
		inc pocetakNiza
		call CitajBroj    ; Ucitali smo M.
		mov N,ax
		inc pocetakNiza
		call CitajBroj
		mov M,ax          ; Ucitali smo N.
		inc pocetakNiza
		call CitajBroj
		mov Lmax,ax       ; Ucitali smo Lmax.

		mWrite "Unesite zeljeno ime izlaznog fajla: "
		mov edx,OFFSET outfilename
		mov ecx,SIZEOF outfilename
		call ReadString

		call CreateOutputFile
		mov  outfileHandle,eax

		; Prepisujemo prva cetiri reda u izlazni fajl.
		; Po izlasku iz petlje rucno upisujemo buffer[0], jer za vrednost ECX=0 nismo prosli kroz petlju.
		mov ecx,pocetakNiza
		Prepisivanje:
		mov al,buffer[ecx]
		mov outbuffer[ecx],al
		loop Prepisivanje

		mov al,buffer[0]
		mov outbuffer[ecx],al

		inc pocetakNiza     ; PocetakNiza pokazuje na prvi pixel.
		mov eax,pocetakNiza
		mov outindex,eax
		
		mov eax, offset buffer
		add eax, velicinaBafera
		mov krajBuffera, eax

		ret
	Uvod ENDP
	
	
	IzdvajanjePixela PROC
		mov eax, offset ulazniPixeli
		xor eax, eax
		xor ecx, ecx
		mov ax, M
		mul N
		mov cx, ax
		xor edi, edi
	upisuj:
		call CitajBroj
		mov ulazniPixeli[edi*2], ax
		inc pocetakNiza
		inc edi
		loop upisuj

		ret

	IzdvajanjePixela ENDP

	;						ObradaSlike
; Ova procedura sluzi za skaliranje slike. Definisu se nove dimenzije slike 
; u zavisnosti od toga da li korisnik zeli da poveca ili da smanji sliku i u zavisnosti
; od parametra s (faktor za skaliranje slike).
; Skaliranje slike se radi pomocu formula date u specifikaciji projekta	
	ObradaSlike PROC
		mov ax, s 
		imul ax, M 
		mov newM, ax
	
		mov ax, s
		imul ax, N
		mov newN, ax 
	
		imul ax, newM

		xor ecx, ecx
		mov cx, ax
		xor edi, edi
		xor esi, esi
		xor eax, eax
		xor ebx,ebx
	petlja:
		xor edx, edx      ;definisanje x' i y'
		mov ax, si 
		idiv newN
		mov x_prim, ax
		mov y_prim, dx

		xor edx,edx       ;odrednjivanje x0 i y0
		mov ax,  x_prim
		idiv s
		mov x0, ax

		xor edx, edx
		mov ax,  y_prim
		idiv s
		mov y0, ax

		mov bx, s         ;odrednjivanje xr i yr
		imul bx, x0
		mov ax, x_prim
		sub ax, bx
		mov xr, ax

		mov bx, s
		imul bx, y0
		mov ax, y_prim
		sub ax, bx
		mov yr, ax

		mov ax, s       ; odredjivanje koji se pixel prepisuje
		sub ax, xr
		cmp xr, ax
		jl manjixr
		mov ax, x0
		inc ax
		imul N
		mov indexIn, ax
		jmp dalje
	manjixr:
		mov ax, x0
		imul N
		mov indexIn, ax
	dalje:

		mov ax, s
		sub ax, yr
		cmp yr, ax
		jl manjiyr
		mov ax, y0
		inc ax
		add indexIn, ax
		jmp dodela
	manjiyr:
		mov ax, y0
		add indexIn, ax
	
	dodela:
		mov di, indexIn
		mov ax, ulazniPixeli[edi*2]
		mov izlazniPixeli[esi*2], ax

		inc esi
		dec cx
		jnz petlja
	
		ret
	ObradaSlike ENDP

	Decimacija PROC
		xor edx, edx
		mov ax, M
		idiv s
		mov newM, ax
	
		xor edx, edx
		mov ax, N
		idiv s
		mov newN, ax
	
		xor esi, esi
		xor edi, edi
		xor ecx, ecx
		xor edx,edx
		mov ax, M
		imul N
		mov duzina, ax
	
	petlja:
		
		xor edx, edx
		mov ax, si
		idiv N
		mov x0, ax
		mov y0, dx
		
		xor edx, edx
		mov ax, x0
		idiv s
		cmp dx, 0
		jnz preskociRed
		
		xor edx, edx
		mov ax, y0
		idiv s
		cmp dx, 0
		jnz dalje
	
		mov ax, ulazniPixeli[esi*2]
		mov izlazniPixeli[edi*2], ax
		inc edi
	dalje:
		inc esi
		jmp provera
	
	preskociRed:
		add si, N
	
	provera:
		cmp si, duzina
		jnz petlja
	
		ret
	Decimacija ENDP

;				IzlazIspis
; Ova procedura sluzi za ispisivanje slike u izlazni fajl.
; Petlja NoviIzlazni popunjava outbuffer vrednostima niza pixeli[].
; Da bismo popunili outbuffer moramo pretvoriti INT u CHAR, tako da vrsimo proveru broja cifara INT,
; a zatim na tu vrednost dodajemo 30h i tako dobijamo ascii vrednost broja.	
	IzlazIspis PROC

		mov edx,OFFSET izlazniPixeli
		xor ebx,ebx
		xor edx,edx

		mov ax, newM
		mul newN
		mov brojac,ax;

		xor eax,eax
		xor ebx,ebx;// EBX je indeks od outbuffer BYTE, dok je EDI indeks od izlazniPixeli WORD.
		xor edi,edi
		mov ebx,outindex

	NoviIzlazni:
		
		xor edx, edx
		mov ax, brojac
		idiv zaNoviRed
		cmp dx, 0
		je noviRed
		jmp preskoci

	noviRed:
		mov outbuffer[edi], 0ah

	preskoci:	
		mov ax,izlazniPixeli[edi]   ; DA LI DA MNOZIM SA 2
		xor edx,edx
		div STOTINA
		cmp ax,0

		je Dvocifren
	Trocifren:;// Trocifreni broj
		mov cifra,3
		add al,30h
		mov broj[0],al;// Stotine
		mov ax,dx
		xor edx,edx
		div DESETICA
		add al,30h
		add dl,30h
		mov broj[1],al;// Desetice
		mov broj[2],dl;// Jedinice
		jmp Ispis

	Dvocifren:;// Dvocifreni broj
		mov cifra,2
		mov al,dl
		xor edx,edx
		div DESETICA
		cmp al,0
		je Jednocifren
		add al,30h
		add dl,30h
		mov broj[0],al;// Desetice
		mov broj[1],dl;// Jedinice
		jmp Ispis

	Jednocifren:;// Jednocifreni broj
		mov cifra,1
		add dl,30h
		mov broj[0],dl;// Jedinice

	Ispis:
		xor edx,edx
		xor eax,eax
		mov eax,edi;// EAX sada cuva index od izlazniPixeli[] dok koristimo EDI za index niza broj.
		xor edi,edi
	Dodavanje:
		mov dl,broj[edi]
		mov outbuffer[ebx],dl
		inc ebx
		inc edi
		dec cifra
		cmp cifra,0
		jnz Dodavanje
		mov outbuffer[ebx],20h;// Ne povecavamo ebx, zato sto se to radi u labeli Sledeci.

		inc ebx
		mov edi,eax
		inc edi
		inc edi

		dec brojac
		cmp brojac,0
		jne NoviIzlazni

		mov  eax, outfileHandle
		mov  edx, OFFSET outbuffer
		mov  ecx, BUFFER_SIZE
		call WriteToFile

		ret

IzlazIspis ENDP
	
	
	
	main PROC

		mWrite <"Unesite ime slike u .pgm formatu: ">
		mov	edx,OFFSET filename
		mov	ecx,SIZEOF filename
		call ReadString

		mov	edx,OFFSET filename
		call OpenInputFile
		mov	fileHandle,eax

		cmp	eax,INVALID_HANDLE_VALUE
		jne	file_ok
		mWrite <"Greska pri otvaranju fajla.",0dh,0ah>
		call WriteWindowsMsg
		jmp	quit

	file_ok:
		mov	edx,OFFSET buffer
		mov	ecx,BUFFER_SIZE
		call ReadFromFile
		jnc	check_buffer_size
	
		mWrite <"Greska pri citanju fajla. ",0dh,0ah>
		call WriteWindowsMsg
		mov eax, fileHandle
		call	close_file
		jmp quit

		check_buffer_size:
		cmp	eax,BUFFER_SIZE
		jbe	buf_size_ok

		mWrite <"Greska: Dimenzije slike su prevelike.",0dh,0ah>
		call WriteWindowsMsg
		mov eax, fileHandle
		call	close_file
		jmp quit

	buf_size_ok:
		mov velicinaBafera,eax

		call Uvod
		call IzdvajanjePixela
		
		mWrite "Unesite faktor skaliranja slike: "
		mov edx, OFFSET broj
		mov ecx, SIZEOF broj
		call ReadString

		mov broj[eax], 3

		mov edx,OFFSET broj
		mov ecx,eax
		call ParseDecimal32
		mov s, ax
		
		mWrite "Za povecanje slike unesite 1, a za decimaciju 0: "
		call ReadChar

		cmp al, 31h
		jz uvecanje
		call Decimacija
		jmp kraj
	uvecanje:
		call ObradaSlike
	kraj:

		call IzlazIspis

		mov  eax,outfileHandle
		call CloseFile
	
		mov	eax,fileHandle
		call CloseFile

	quit:
		exit
	main ENDP
	END main