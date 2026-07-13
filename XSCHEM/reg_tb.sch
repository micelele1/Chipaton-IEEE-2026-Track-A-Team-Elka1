v {xschem version=3.4.8RC file_version=1.3}
G {}
K {}
V {}
S {}
F {}
E {}
N 840 -650 840 -640 {lab=#net1}
N 840 -660 840 -650 {lab=#net1}
N 840 -660 1000 -660 {lab=#net1}
N 920 -635 920 -580 {lab=#net2}
N 920 -640 920 -635 {lab=#net2}
N 920 -640 1000 -640 {lab=#net2}
N 1000 -620 1000 -585 {lab=#net3}
N 755 -705 975 -705 {lab=#net4}
N 975 -705 975 -700 {lab=#net4}
N 975 -700 1000 -700 {lab=#net4}
N 785 -675 785 -585 {lab=#net5}
N 785 -680 785 -675 {lab=#net5}
N 785 -680 1000 -680 {lab=#net5}
C {vsource.sym} 840 -610 0 0 {name=clk value=pulse(0 1.8 0 100p 100p 5n 10n) savecurrent=false}
C {vsource.sym} 1000 -555 0 0 {name=rst value=pulse(0 1.8 0 100p 100p 20n 100n) savecurrent=false}
C {vsource.sym} 920 -550 0 0 {name=set value=pulse(1.8 0 30p 100p 100p 10n 100n) savecurrent=false}
C {gnd.sym} 1000 -525 0 0 {name=l1 lab=0}
C {gnd.sym} 840 -580 0 0 {name=l2 lab=0}
C {gnd.sym} 920 -520 0 0 {name=l3 lab=0}
C {vsource.sym} 755 -675 0 0 {name=D0 value=pulse(0 1.8 0 100p 100p 100n 200n) savecurrent=false}
C {vsource.sym} 785 -555 0 0 {name=D1 value=pulse(0 1.8 0 100p 100p 200n 400n) savecurrent=false}
C {/workspace/XSCHEM/state_reg.sym} 1150 -660 0 0 {name=x1}
C {code.sym} 1070 -560 0 0 {name=s1 only_toplevel=false value=blab}
