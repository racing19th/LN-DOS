;all functions here use the cdecl calling convention unless specified otherwise
BITS 32

extern hexprint

SECTION .text

global initVga:function
initVga:	;(void) returns void
		call getCRTCPorts
		call vgaGetScreenWidth
		;shr eax, 1
		mov [screenWidth], eax
		call vgaGetScreenHeight
		mov [screenHeight], eax
		call getvirt_ychars
		mov [vscreen_ychars], ax
		
		ret

getCRTCPorts:	;(void) returns void
		mov dx, 0x3CC ;misc output port
		in al, dx
		test al, 0x01 ;test first bit
		jnz .end ;leave to default
		mov ax, 0x3B4
		mov [CRTCIndexPort], ax
		mov ax, 0x3B5
		mov [CRTCDataPort], ax
	.end:	ret

getvirt_ychars:	;(void) returns short
		xor eax, eax
		mov ax, [vram_size]
		xor edx, edx
		mov ecx, [screenWidth]
		div ecx
		shr ax, 1
		ret

global vgaGetScreenWidth:function
vgaGetScreenWidth:	;(void) returns int width
		push ebp
		mov ebp, esp

		;save the old value in the address register
		mov dx, [CRTCIndexPort]
		in al, dx
		push eax
		;first we need to find out what mode is currently enabled
		;check if dword mode bit is set
		mov al, 0x14
		out dx, al
		mov dx, [CRTCDataPort]
		in al, dx
		test al, 0x40
		jnz .not_dword
		mov cl, 2
		jmp .cont

	.not_dword:
		mov al, 0x17
		mov dx, [CRTCIndexPort]
		out dx, al
		mov dx, [CRTCDataPort]
		in al, dx
		test al, 0x40 ;0b01000000
		jz .byte
	.word:	mov cl, 1
		jmp .cont
	.byte:	mov cl, 0
	.cont:	mov al, 0x13
		mov dx, [CRTCIndexPort]
		out dx, al
		mov dx, [CRTCDataPort]
		xor eax, eax
		in al, dx
		shl eax, cl
		;shr eax, 2
		mov edx, eax
		pop eax
		push edx
		mov dx, [CRTCIndexPort]
		out dx, al
		pop eax
		pop ebp
		ret

global vgaGetScreenHeight:function
vgaGetScreenHeight: ;(void) returns int
		push ebp
		mov ebp, esp
		sub esp, 12

		;save old index value
		mov dx, [CRTCIndexPort]
		in al, dx
		mov [ss:ebp-4], al

		;get maximum scanline per char
		mov al, 0x09 ;maximum scan line register
		out dx, al
		mov dx, [CRTCDataPort]
		in al, dx
		;now AND it to filter out other settings
		and al, 0x1F
		;the field contains the amount of scanlines per char - 1 so we
		;have to increment it
		inc al
		mov [ss:ebp-8], al ;save it for now

		;now get the number of scanlines in the active display
		mov dx, [CRTCIndexPort]
		mov al, 0x12 ;vertical display end register
		out dx, al
		mov dx, [CRTCDataPort]
		in al, dx
		;the 2 higher bits are loaded in the overflow register
		mov [ss:ebp-12], al ;save it for now

		mov dx, [CRTCIndexPort]
		mov al, 0x07
		out dx, al
		mov dx, [CRTCDataPort]

		in al, dx ;get bit 9
		mov ah, al
		and ah, 0x40
		shr ah, 4 ;shift it to bit 1
		in al, dx ;and bit 8
		and al, 0x02
		shr al, 1 ;shift it to bit 0

		or ah, al ;combine them
		mov al, [ss:ebp-12] ;and get the lower 8 bits
		;ax now contains the full 10 bit value
		;clear the high word of eax and clear edx
		mov dx, ax
		xor eax, eax
		mov ax, dx
		xor edx, edx
		;load the amount of scanlines per char
		;xor ecx, ecx
		movzx ecx, byte [ss:ebp-8]
		div ecx ;divide the amount of scanlines by the amount
		;of scanlines per char
		inc eax
		mov [ss:ebp-8], eax ;save the quotient for now

		;restore old index port value
		mov dx, [CRTCIndexPort]
		mov al, [ss:ebp-4]
		out dx, al

		mov eax, [ss:ebp-8] ;restore result
		leave ;and return
		ret

global vgaSetCursor:function
vgaSetCursor:	;(int cursorX, int cursorY) returns void
		;updates VGA cursor position
		push ebp
		mov ebp, esp
		;mov edx, [ss:ebp+8]
		mov eax, [ss:ebp+12]
		mul dword [screenWidth]
		shr eax, 1
		;push eax
		;call hexprint
		;jmp $
		mov edx, eax
		mov eax, [ss:ebp+8]
		;shr eax, 1
		add eax, edx
		mov [ss:ebp+8], eax
		;save old index port
		mov dx, [CRTCIndexPort]
		in al, dx
		mov [ss:ebp+12], al
		;low byte
		mov al, 0x0F
		out dx, al
		mov dx, [CRTCDataPort]
		mov al, [ss:ebp+8]
		out dx, al
		;high byte
		mov al, 0x0E
		mov dx, [CRTCIndexPort]
		out dx, al
		mov al, [ss:ebp+9]
		mov dx, [CRTCDataPort]
		out dx, al

		pop ebp
		ret

global vgaSetScroll:function
vgaSetScroll:	;(int scrollY) returns void
		push ebp
		mov ebp, esp
		sub esp, 8

		mov eax, [ss:ebp+8]
		xor edx, edx
		mov ecx, [screenWidth]
		shr ecx, 1
		mul ecx
		mov [ss:ebp-8], eax ;save the address offset

		mov dx, [CRTCIndexPort]
		in al, dx
		mov [ss:ebp-4], al ;save old index value

		mov al, 0x0D ;start address low
		out dx, al
		mov dx, [CRTCDataPort]
		mov al, [ss:ebp-8]
		out dx, al

		mov dx, [CRTCIndexPort]
		mov al, 0x0C ;start address high
		out dx, al
		mov dx, [CRTCDataPort]
		mov al, [ss:ebp-7]
		out dx, al
		
		mov dx, [CRTCIndexPort]
		mov al, [ss:ebp-4]
		out dx, al ;restore old index port value

		leave
		ret

SECTION .data
global vram:data
vram:		dd 0xC00B8000
vram_size:	dw 0x8000

global scrollY:data
scrollY:	dw 0

CRTCIndexPort: dw 0x03D4
CRTCDataPort: dw 0x03D5

SECTION .bss

vscreen_ychars:	resw 1

global screenWidth:data
screenWidth:	resd 1
global screenHeight:data
screenHeight:	resd 1
