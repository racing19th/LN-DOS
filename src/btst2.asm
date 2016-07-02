BITS 16
;ORG	0x00000
CURRENTSEG	equ	0x0050
FATSEG		equ	0x7000
KRNLSEG		equ	0x0700 ;values above 0800 dont work, idk why

SECTPERTRACK	equ	0x0012
NROFHEADS	equ	0x0002
RESSECTORS	equ	0x0001
NROFFATS	equ	0x0002
NROFFATSECTS	equ	0x0009
NROFROOTDIRENTS	equ	0x00E0

FILEOFFSET	equ	RESSECTORS+(NROFFATSECTS*NROFFATS)+(NROFROOTDIRENTS/16)-1


%define endl	13,10,0

global _stage2
_stage2:	
		push ax
		mov ax, CURRENTSEG
		mov ds, ax
		mov [drivenumber], bl
		pop ax

		mov [currentsector], ax
		mov ax, FATSEG
		mov fs, ax
		mov es, ax
		call loadfattable

		mov ax, CURRENTSEG
		mov es, ax

		mov ax, [currentsector]
		mov cx, 1
		xor dx, dx
		mov bx, 0x0200
		call followfat

		mov si, stage2loadedmsg
		call print
		jmp next

followfat:	;ax = first sector, cx = sectors to skip from start
		;dx = amount of sectors to read 0 = 65536, stops at FAT EOF marker
		;result in [es:bx]
		push bp
		mov bp, sp

	.loop:	push bx
		push ax
		cmp cx, 0
		jne .noload
		push cx
		push dx
		add ax, FILEOFFSET
		mov cl, 1
		call loadsector
		pop dx
		pop cx
		dec dx
		cmp dx, 0
		je .end
		jmp .cont

	.noload:;sub bh, 0x02
		;dec cx

	.cont:	pop ax
		call getfatentry ;should only change ax and bx
		cmp ax, 0x0FF8
		jge .eof
		cmp ax, 0x0FF0
		jge .err
		cmp ax, 0x0001
		jle .err
		pop bx
		jcxz .cont2
		dec cx
		jmp .loop
	.cont2:	add bh, 0x02
		jmp .loop

	.err:	;pointing to bad/reserved sector
		mov si, badsectormsg
		call print
		jmp $

	.end:	pop ax
	.eof:	pop bx
		pop bp
		ret

hexprintbyte:	push bp
		mov bp, sp
		push ax
		and al, 0xF0
		shr al, 4
		call translatenibble
		mov ah, 0x0E
		int 0x10
		
		mov ax, [ss:bp-2]
		;pop ax
		and al, 0x0F
		call translatenibble
		mov ah, 0x0E
		int 0x10
		mov al, ' '
		int 0x10
		pop ax
		pop bp
		ret
		
translatenibble:
		cmp al, 10
		jge .hexchar
		;0-9
		add al, '0'
		ret
	.hexchar: ; A-F
		add al, 'A' - 10
		ret

print:		lodsb
		or al, al
		jz .done
		mov ah, 0x0E
		int 0x10
		jmp print
	.done: 	ret

loadfattable:	mov ax, RESSECTORS + 1
		;mov ax, 1
		mov cl, NROFFATSECTS
		xor bx, bx
		call loadsector
		;mov al, [fs:0]
		;call hexprintbyte
		ret

getfatentry:	;ax = clusternr, fat table in fs, returns ax = table entry value
		call getposfromcluster
		mov bx, ax
		;pushf
		;mov al, [fs:bx]
		;call hexprintbyte
		;mov al, [fs:bx+1]
		;call hexprintbyte
		;popf
		jc .pos2

	.pos1:	mov al, [fs:bx]
		mov ah, [fs:bx+1]
		and ax, 0x0FFF
		jmp .end

	.pos2:	mov al, [fs:bx]
		mov ah, [fs:bx+1]
		and al, 0xF0
		shr ax, 4

	.end:	ret
		
getposfromcluster: ;ax = clusternr, carry = offset 0 or 1
		push ax
		shr ax, 1
		mov bx, ax
		pop ax
		pushf
		add ax, bx
		xor bx, bx
		popf
	.end:	ret	

loadsector:	;sector number in AX, result in ES:BX, sectors to read in cl
		push bx
		push cx
		push ax
		mov ah, 0
		mov dl, [drivenumber]
		int 0x13
		
		pop ax
		dec ax
		mov bl, SECTPERTRACK*NROFHEADS
		div bl
		mov ch, al	;track

		mov al, ah
		xor ah, ah
		mov bl, SECTPERTRACK
		div bl
		mov dh, al	;head number
		mov cl, ah	;sector
		inc cl

		pop bx
		mov al, bl	;sectors to read
		pop bx
		mov ah, 02h	;instruction code
		mov dl, [drivenumber]
	.retry:	int 0x13
		jc .retry
		ret


drivenumber:	db	0
currentsector:	dw	0
stage2loadedmsg:db	"Loaded stage 2", endl
badsectormsg:	db	"ERROR: bad sector detected!", endl


next:		call test_a20 ;test if A20 is already enabled
		or al, al
		jnz .a20en
		call init_a20 ;if not, enable A20 via the keyboard controller
		call test_a20
		or al, al
		jz .a20err
	.a20en:	mov si, a20enabledmsg
		call print
		jmp .next0
	.a20err:mov si, a20errormsg
		call print
		jmp $
	.next0:	;jmp $
		call load_krnl
		;jmp $

		call pmode
		;jmp $
		mov ax, 0x18
		mov es, ax
		xor bx, bx
		mov [es:00], byte 'K'

		;Now we hand the system over to the kernel
		mov ax, 0x0010
		mov fs, ax
		mov gs, ax
		mov ds, ax
		mov ax, 0x0018
		mov es, ax
		jmp 8:0 ;bye

test_a20:	pushf
		push ds
		push es
		push di
		push si

		cli
		
		xor ax, ax
		mov es, ax

		not ax
		mov ds, ax

		mov ax, [es:0x7DFE]
		cmp ax, [ds:0x7E0E]
		jne .yes
		mov ax, 0xABCD
		mov [es:0x7DFE], ax
		cmp ax, [ds:0x7E0E]
		jne .yes
		mov ax, 0
		jmp .end

	.yes:	mov ax, 1


	.end:	pop si
		pop di
		pop es
		pop ds
		popf
		ret

init_a20:	push ax
		cli

		call kyb_wait_in
		mov al, 0xAD
		out 0x64, al ;disable input

		call kyb_wait_in
		mov al, 0xD0
		out 0x64, al

		call kyb_wait_out
		in al, 0x60
		push ax

		call kyb_wait_in
		mov al, 0xD1
		out 0x64, al

		call kyb_wait_in
		pop ax
		or al, 2
		out 0x60, al

		call kyb_wait_in
		mov al, 0xAE
		out 0x64, al

		call kyb_wait_in
		sti
		pop ax
		ret


kyb_wait_in:	in al, 0x64 ;read status
		test al, 2 ;check if input buffer flag is clear
		jnz kyb_wait_in
		ret

kyb_wait_out:	in al, 0x64
		test al, 1
		jz kyb_wait_out
		ret

load_krnl:	mov ax, KRNLSEG
		mov es, ax
		call hexprintbyte
		mov al, ah
		call hexprintbyte
		xor bx, bx
		mov ax, RESSECTORS + (NROFFATS * NROFFATSECTS) + 1
		mov cl, NROFROOTDIRENTS/16
		call loadsector
		call hexprintbyte

		;Root dir entries are now loaded
		xor cx, cx
	.start:	cmp cx, NROFROOTDIRENTS
		je .nfound ;if it has run out of entries to look in
		mov bx, cx
		shl bx, 5 ;times 32 to get address
		mov si, krnlfilename
	.start2:mov al, bl
		and al, 0x0F
		cmp al, 0x0B
		je .found
		lodsb
		cmp al, [es:bx]
		pushf
		inc bl
		popf
		je .start2

	.end2:	inc cx
		;push cx
		mov al, cl
		jmp .start
	
	.nfound:mov si, krnlnfounderror
		call print
		jmp $

	.found:	and bl, 0xF0
		add bx, 0x1A ;start of file cluster nr
		mov ax, [es:bx]
		mov [krnlsector], ax

		mov si, krnlfoundmsg
		call print

		mov ax, KRNLSEG
		mov es, ax
		;fat table should still be loaded in fs

		mov ax, [krnlsector]
		add ax, FILEOFFSET
		;clc
		;call followfat
		;first we need to load in the first cluster to interpret the ELF header
		xor bx, bx
		mov cl, 1
		call loadsector
		;ok now we need to verify if the 'magic' bytes are correct
		cmp [es:0x0000], word 0x457F ;0x7F & 0x45 ('E')
		jne .ferror
		cmp [es:0x0002], word 0x464C ;0x4C & 0x46 ('LF') remember, we use little endian
		jne .ferror
		;now that the magic bytes are verified, we need to make sure the file is
		;32 bit and little endian (other modes are not supported)
		cmp [es:0x0004], word 0x0101
		jne .ferror ;I should probably make more error messages, oh well
		;Now check the instruction set
		cmp [es:0x0012], word 0x0003 ;x86
		jne .ferror

		;Let's now get the program header
		;make sure that the 9 most significant bits are cleared
		cmp [es:0x001F], byte 0x00
		jne .ferror
		test [es:0x001E], byte 0x80
		jnz .ferror
		;now get the program header position, the least significant byte doesnt matter
		;as we are just looking at the cluster it is in
		mov ax, [es:0x001D] ;here we are looking into the 2 middle bytes
		shr ax, 1 ;divide it by 2 to get relative cluster nr
		mov [progheadcluoffset], ax
		;now we need to get the offset from the cluster in bytes
		mov ax, [es:0x001C]
		and ax, 0x01FF ;only the lowest 9 bits matter
		mov [progheadboffset], ax
		;as well as the number of entries
		mov ax, [es:0x002C]
		mov [progheadsize], ax
		;now get the total program header table size in bytes
		mov dx, [es:0x002E]
		mul dx ;and multiply it to get the size in bytes
		mov [progheadsizeb], ax
		shr ax, 9 ;divide by 512 for the amount of clusters
		inc al
		mov [progheadsizecluster], al
		;and we also need the size 1 entry takes up
		mov ax, word [es:0x002A]
		mov [progheadentsize], ax

		;Ok now we need to set es
		mov ax, 0x7E00
		mov dx, [progheadsizeb]
		shr dx, 4
		inc dx ;to account for the last cluster
		sub ax, dx
		mov es, ax
		;now we can finally start loading in the program headers
		xor bx, bx
		mov cx, [progheadcluoffset]
		mov dl, [progheadsizecluster]
		xor dh, dh
		mov ax, [krnlsector]
		call followfat

		mov bx, [progheadboffset]
		mov cx, [progheadsize]
		;now we have to decode the header entries
	.start3:jcxz .succ
		mov al, [es:bx]
		cmp al, 0
		je .end3 ;skip null header
		cmp al, 1
		je .cont
		call .perror
		jmp .end3 ;skip it

	.cont:	call progheaddecode

	.end3:	add bx, 0x0020
		dec cx
		jmp .start3
		
	.perror:mov si, progheadnoload
		call print
		jmp $

	.ferror:mov si, krnlformaterror
		call print
		jmp $

	.succ:	mov si, krnlloadedmsg
		call print

		ret

progheaddecode:	;this function decodes a program header table entry and executes it
		push bp
		mov bp, sp
		;stack map:
		;-2h cx reserved
		;-4h bx program header offset
		;-6h old es
		;-8h old ds
		;-Ah buffer segment
		;-Ch destination segment
		;-Eh current bytes remaining (low)
		;-10h current bytes remaining (high)
		;-12h current file offset (low)
		;-14h current file offset (high)
		;-16h current memory offset (low) unused
		;-18h current memory offset (high) unused
		sub sp, 0x18
		mov [ss:bp-0x2], cx
		mov [ss:bp-0x4], bx
		mov ax, es
		mov [ss:bp-0x6], ax
		mov ax, ds
		mov [ss:bp-0x8], ax

		mov ax, KRNLSEG
		mov [ss:bp-0xC], ax ;destination segment
		sub ax, 0x0020
		mov [ss:bp-0xA], ax ;buffer segment
		
		mov ax, [es:bx+16]
		mov [ss:bp-0xE], ax ;current bytes remaining (low)
		mov ax, [es:bx+18]
		mov [ss:bp-0x10], ax ;high

		mov ax, [es:bx+4]
		mov [ss:bp-0x12], ax ;current file offset (low)
		mov ax, [es:bx+6]
		mov [ss:bp-0x14], ax ;high

		mov ax, [es:bx+8]
		mov [ss:bp-0x16], ax ;current memory offset (low)
		mov ax, [es:bx+10]
		mov [ss:bp-0x18], ax ;high

	.start:	;first we need the cluster nr
		;code must be aligned to 0x200
		mov ax, [ss:bp-0x14] ;high word first
		shl eax, 16 ;and shift it
		mov ax, [ss:bp-0x12] ;low word
		shr eax, 9 ;divide it 512 times to get cluster nr
		
		;now load it into buffer
		mov cx, ax
		mov ax, [ss:bp-0x8]
		mov ds, ax
		mov ax, [ss:bp-0xA]
		mov es, ax
		xor bx, bx
		mov dx, 1
		mov ax, [krnlsector]
		call followfat

		;now get the amount of bytes to copy from the buffer, capped at 0x200
		mov ax, [ss:bp-0xE]
		cmp ax, 0x200
		jle .cont
		mov ax, 0x200
	.cont:	xor ecx, ecx
		mov cx, ax
		
		;set ds to buffer and es to destination
		mov ax, es ;buffer segment should still be in es
		mov ds, ax
		mov ax, [ss:bp-0xC]
		mov es, ax

		mov si, 0
		mov di, 0

		rep movsb

		;check the current bytes remaining
		mov ax, [ss:bp-0x10]
		shl eax, 16
		mov ax, [ss:bp-0xE]
		;and decrease it by 512
		sub eax, 0x200
		jl .done ;if the bytes remaining was less than 512, we're done
		mov [ss:bp-0xE], ax ;store low
		shr eax, 16
		mov [ss:bp-0x10], ax ;and high

		;now update destination segment
		mov ax, [ss:bp-0xC]
		add ax, 0x0020
		mov [ss:bp-0xC], ax

		;and the file offset
		mov ax, [ss:bp-0x14]
		shl eax, 16
		mov ax, [ss:bp-0x12]
		add eax, 0x200
		mov [ss:bp-0x12], ax
		shr eax, 16
		mov [ss:bp-0x14], ax
		jmp .start

	.done:	mov ax, [ss:bp-0x6]
		mov es, ax
		mov ax, [ss:bp-0x8]
		mov ds, ax

		mov cx, [ss:bp-0x2]
		mov bx, [ss:bp-0x4]
		mov sp, bp
		pop bp
		ret

pmode:		cli
		lgdt [gdtr]
		mov eax, cr0
		or eax, 1
		mov cr0, eax

		ret

krnlsector:	dw 0

a20enabledmsg:	db 'A20 line is enabled', endl
a20errormsg:	db 'ERROR: Could not enable A20', endl

krnlfilename:	db 'KERNEL     '
krnlnfounderror:db 'ERROR: File ', 0x60, 'KERNEL', 0x60, ' could not be found!', endl
krnlfoundmsg:	db 'KERNEL found, loading...', endl
krnlloadedmsg:	db 'KERNEL loaded!', endl
krnlformaterror:db 'KERNEL format error', endl

progheadnoload:	db 'WARN: KERNEL Program header contains unsupported mode, skipping...', endl
progheadcluoffset:	dw 0
progheadboffset:dw 0
progheadsize:	dw 0
progheadsizeb:	dw 0
progheadsizecluster:	db 0
progheadentsize:	dw 0

gdtr:		dw 0x1F ;size
		dd gdt+(CURRENTSEG * 16) ;offset

gdt:		;first, a null descriptor 0x00
		dq 0
		;code descriptor 0x08, base 0, limit 0xffffffff, type 0x9A
		dw 0xFFFF ;limit 0:15
		dw KRNLSEG * 16 ;base 0:15
		db 0x00   ;base 16:23
		db 10011010b ;access byte
		db 0xCF   ;flags & limit 16:19
		db 0x00   ;base 24:31
		;data descriptor 0x10, base 0, limit 0xffffffff, type 0x92
		dw 0xFFFF ;limit 0:15
		dw KRNLSEG * 16 ;base 0:15
		db 0x00   ;base 16:23
		db 10010010b ;access byte
		db 0xCF   ;flags & limit 16:19
		db 0x00   ;base 24:31
		;video descriptor 0x18, base 0x0000b800, limit 0x0000ffff, type 0x92
		dw 0xFFFF ;limit 0:15
		dw 0x8000 ;base 0:15
		db 0x0B   ;base 16:23
		db 10010010b ;access byte
		db 0xCF   ;flags & limit 16:19
		db 0x00   ;base 24:31

