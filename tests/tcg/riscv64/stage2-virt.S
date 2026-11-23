/* Minimal G-stage.Virt test for RV64 TCG. */
	.option norvc

	.equ PTE_V, 0x001
	.equ PTE_R, 0x002
	.equ PTE_W, 0x004
	.equ PTE_X, 0x008
	.equ PTE_U, 0x010
	.equ PTE_A, 0x040
	.equ PTE_D, 0x080
	.equ PTE_STAGE2_VIRT, 0x100
	.equ MSTATUS_MPP_SHIFT, 11
	.equ MSTATUS_MPP_MASK, (3 << MSTATUS_MPP_SHIFT)
	.equ MSTATUS_MPV, 0x8000000000
	.equ HGATP_MODE_SV39X4, (8 << 60)
	.equ CAUSE_VU_ECALL, 8
	.equ CAUSE_VS_ECALL, 10
	.equ CAUSE_INST_GPF, 20
	.equ CAUSE_STORE_GPF, 23
	.equ GUEST_RAM_BASE, 0x80000000

	.section .text
	.global _start
	.type _start, @function
_start:
	la t0, machine_trap
	csrw mtvec, t0
	csrw medeleg, zero
	csrw hedeleg, zero

	/* Sv39x4 root index 2 covers the 0x80000000 guest region. */
	la t0, gstage_root
	la t1, gstage_l1
	srli t1, t1, 2
	ori t1, t1, PTE_V
	sd t1, 16(t0)
	la t0, gstage_l1
	la t1, gstage_l0
	srli t1, t1, 2
	ori t1, t1, PTE_V
	sd t1, 0(t0)

	/* Identity-map the first 2 MiB with RWXU leaf PTEs. */
	la t0, gstage_l0
	li t1, GUEST_RAM_BASE
	li t2, 512
	li t3, PTE_V | PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D
	li t5, 4096
1:
	srli t4, t1, 2
	or t4, t4, t3
	sd t4, 0(t0)
	addi t0, t0, 8
	add t1, t1, t5
	addi t2, t2, -1
	bnez t2, 1b

	/* Target page: R|U|A|D|STAGE2_VIRT, with no base W/X. */
	la t0, gstage_l0
	la t1, stage2_target
	li t2, GUEST_RAM_BASE
	sub t1, t1, t2
	srli t1, t1, 12
	slli t1, t1, 3
	add t0, t0, t1
	la t1, stage2_target
	srli t1, t1, 2
	li t2, PTE_V | PTE_R | PTE_U | PTE_A | PTE_D | PTE_STAGE2_VIRT
	or t1, t1, t2
	sd t1, 0(t0)

	la t0, gstage_root
	srli t0, t0, 12
	li t1, HGATP_MODE_SV39X4
	or t0, t0, t1
	csrw hgatp, t0
	hfence.gvma
	csrw vsatp, zero

	li t0, CAUSE_VU_ECALL
	la t1, expected_cause
	sd t0, 0(t1)
	la t0, vu_read
	j enter_vu

dispatch:
	la t0, phase
	ld t1, 0(t0)
	addi t1, t1, 1
	sd t1, 0(t0)
	li t2, 1
	beq t1, t2, dispatch_vu_write
	li t2, 2
	beq t1, t2, dispatch_vu_exec
	li t2, 3
	beq t1, t2, dispatch_vs_read
	li t2, 4
	beq t1, t2, dispatch_vs_write
	li t2, 5
	beq t1, t2, dispatch_vs_exec
	li t2, 6
	beq t1, t2, test_pass
	j test_fail

dispatch_vu_write:
	li t0, CAUSE_VU_ECALL
	la t1, expected_cause
	sd t0, 0(t1)
	la t0, vu_write
	j enter_vu
dispatch_vu_exec:
	li t0, CAUSE_VU_ECALL
	la t1, expected_cause
	sd t0, 0(t1)
	la t0, vu_exec
	j enter_vu
dispatch_vs_read:
	li t0, CAUSE_VS_ECALL
	la t1, expected_cause
	sd t0, 0(t1)
	la t0, vs_read
	j enter_vs
dispatch_vs_write:
	li t0, CAUSE_STORE_GPF
	la t1, expected_cause
	sd t0, 0(t1)
	la t0, vs_write
	j enter_vs
dispatch_vs_exec:
	li t0, CAUSE_INST_GPF
	la t1, expected_cause
	sd t0, 0(t1)
	la t0, vs_exec
	j enter_vs

enter_vu:
	li t1, MSTATUS_MPP_MASK | MSTATUS_MPV
	csrr t2, mstatus
	not t3, t1
	and t2, t2, t3
	li t3, MSTATUS_MPV
	or t2, t2, t3
	csrw mstatus, t2
	csrw mepc, t0
	mret
enter_vs:
	li t1, MSTATUS_MPP_MASK | MSTATUS_MPV
	csrr t2, mstatus
	not t3, t1
	and t2, t2, t3
	li t3, MSTATUS_MPV | (1 << MSTATUS_MPP_SHIFT)
	or t2, t2, t3
	csrw mstatus, t2
	csrw mepc, t0
	mret

vu_read:
	la t0, stage2_target_data
	ld t1, 0(t0)
	ecall
vu_write:
	la t0, stage2_target_data
	li t1, 42
	sd t1, 0(t0)
	ecall
vu_exec:
	la t0, stage2_target
	jalr ra, t0, 0
	ecall
vs_read:
	la t0, stage2_target_data
	ld t1, 0(t0)
	ecall
vs_write:
	la t0, stage2_target_data
	li t1, 42
	sd t1, 0(t0)
	ecall
vs_exec:
	la t0, stage2_target
	jalr ra, t0, 0
	ecall

machine_trap:
	csrr t0, mcause
	la t1, expected_cause
	ld t1, 0(t1)
	bne t0, t1, test_fail
	csrr t0, mstatus
	li t1, MSTATUS_MPV
	not t1, t1
	and t0, t0, t1
	li t1, MSTATUS_MPP_MASK
	or t0, t0, t1
	csrw mstatus, t0
	la t0, dispatch
	csrw mepc, t0
	mret

test_pass:
	li a0, 0
	j semihost_exit
test_fail:
	li a0, 1
semihost_exit:
	la a1, semiargs
	li t0, 0x20026
	sd t0, 0(a1)
	sd a0, 8(a1)
	li a0, 0x20
	.balign 16
	slli zero, zero, 0x1f
	ebreak
	srai zero, zero, 0x7
	j .

	.balign 4096
	.type stage2_target, @function
stage2_target:
	li a0, 42
	ret
	.balign 8
stage2_target_data:
	.dword 0

	.section .bss
	.balign 16384
gstage_root:
	.space 16384
	.balign 4096
gstage_l1:
	.space 4096
	.balign 4096
gstage_l0:
	.space 4096
	.balign 8
phase:
	.dword 0
expected_cause:
	.dword 0

	.section .data
	.balign 8
semiargs:
	.space 16
