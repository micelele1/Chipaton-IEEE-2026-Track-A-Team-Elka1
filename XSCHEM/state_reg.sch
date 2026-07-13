v {xschem version=3.4.8RC file_version=1.3}
G {}
K {}
V {}
S {}
F {}
E {}
N 960 -790 980 -790 {lab=CLK}
N 960 -790 960 -700 {lab=CLK}
N 960 -700 980 -700 {lab=CLK}
N 970 -750 980 -750 {lab=RST}
N 970 -750 970 -660 {lab=RST}
N 970 -660 980 -660 {lab=RST}
N 950 -730 980 -730 {lab=SET}
N 950 -730 950 -640 {lab=SET}
N 950 -640 980 -640 {lab=SET}
N 950 -770 980 -770 {lab=state_in[0]}
N 950 -790 950 -770 {lab=state_in[0]}
N 930 -790 950 -790 {lab=state_in[0]}
N 940 -680 980 -680 {lab=state_in[1]}
N 940 -770 940 -680 {lab=state_in[1]}
N 930 -770 940 -770 {lab=state_in[1]}
N 930 -750 960 -750 {lab=CLK}
N 930 -730 950 -730 {lab=SET}
N 930 -710 970 -710 {lab=RST}
N 1160 -790 1200 -790 {lab=state[0]}
N 1160 -700 1180 -700 {lab=state[1]}
N 1180 -770 1180 -700 {lab=state[1]}
N 1180 -770 1200 -770 {lab=state[1]}
C {/foss/pdks/sky130A/libs.tech/xschem/sky130_stdcells/dfbbp_1.sym} 1070 -760 0 0 {name=x1 VGND=VGND VNB=VNB VPB=VPB VPWR=VPWR prefix=sky130_fd_sc_hd__ }
C {/foss/pdks/sky130A/libs.tech/xschem/sky130_stdcells/dfbbp_1.sym} 1070 -670 0 0 {name=x2 VGND=VGND VNB=VNB VPB=VPB VPWR=VPWR prefix=sky130_fd_sc_hd__ }
C {ipin.sym} 930 -790 0 0 {name=p1 lab=state_in[0]}
C {ipin.sym} 930 -770 0 0 {name=p2 lab=state_in[1]}
C {ipin.sym} 930 -750 0 0 {name=p3 lab=CLK}
C {ipin.sym} 930 -730 0 0 {name=p4 lab=SET}
C {ipin.sym} 930 -710 0 0 {name=p5 lab=RST}
C {opin.sym} 1200 -790 0 0 {name=p6 lab=state[0]}
C {opin.sym} 1200 -770 0 0 {name=p7 lab=state[1]}
