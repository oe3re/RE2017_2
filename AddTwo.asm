.386
.model flat,stdcall
.stack 4096
ExitProcess proto,dwExitCode:dword

.code
main proc
      mov ecx, 0FFFF0000h
      nop
      nop
      jcxz petlja

      nop
      nop

petlja:

      nop
      nop
	invoke ExitProcess,0
main endp
end main