// Semantic checks for the current 194-word register checkpoint, not a complete
// machine schema. Feed only validated descriptor-order payload words. This
// scanner never writes guest state; staged bytes remain locked until commit.
module gba_state_register_validator #(
    parameter integer TICK_DENOMINATOR=4875,
    parameter integer DISPLAY_LINE_CYCLES=1232
)(
    input wire clk,reset,start,word_valid,
    input wire [31:0] word_index,word_data,
    output reg word_ok
);
    reg [7:0] next_word;
    reg [1:0] pc_low;
    reg cpsr_thumb;
    reg cpsr_fiq;
    reg [7:0] captured_vcount;
    reg [2:0] eeprom_state;
    reg [6:0] rtc_bits;
    reg rtc_active;
    function automatic mode_valid(input [4:0] mode);
        case(mode)
            5'h10,5'h11,5'h12,5'h13,5'h17,5'h1b,5'h1f:mode_valid=1;
            default:mode_valid=0;
        endcase
    endfunction
`ifdef GBK_LINK_MULTIPLAYER
    // Explicit parallel rejection terms avoid a synthesized priority chain
    // across disjoint checkpoint indices. Kept sixteen-word groups bound the
    // reduction depth without changing any acceptance or transaction cycle.
    wire [207:0] parallel_reject;
    (* keep *) wire [12:0] parallel_reject_group;
    assign parallel_reject[16]=(word_index[7:0]==8'd16) && !(mode_valid(word_data[4:0]));
    assign parallel_reject[17]=(word_index[7:0]==8'd17) && !(word_data[31:2]==0 &&
                word_data[0]==cpsr_thumb && (word_data[0] ? !pc_low[0] : pc_low==0));
    assign parallel_reject[45]=(word_index[7:0]==8'd45) && !(word_data<TICK_DENOMINATOR);
    assign parallel_reject[46]=(word_index[7:0]==8'd46) && !(word_data[31:12]==0);
`ifdef GBK_GAMEPAK_PREFETCH
            // Word 47 holds prefetch state [19:0]. Word 48 holds [45:20]:
            // next address [25:0], credit [32:26], valid [33], WAITCNT key.
            // Credit is measured in sequential service cycles (maximum 8*9).
    assign parallel_reject[48]=(word_index[7:0]==8'd48) && !(word_data[18:12]<=72 &&
                (word_data[19] ? (word_data[31] && word_data[11:9]<6 &&
                    word_data[18:12]<=(word_data[11:9]<2 ? (word_data[24] ? 16 : 24) :
                        word_data[11:9]<4 ? (word_data[27] ? 16 : 40) : (word_data[30] ? 16 : 72))) :
                    word_data[18:12]==0));
`else
    assign parallel_reject[47]=(word_index[7:0]==8'd47) && !(word_data[31:12]==0);
    assign parallel_reject[48]=(word_index[7:0]==8'd48) && !(word_data[31:6]==0);
`endif
    assign parallel_reject[84]=(word_index[7:0]==8'd84) && !(word_data[31:10]==0 && word_data[6:4]<=4 && word_data[9:7]<=4);
    assign parallel_reject[85]=(word_index[7:0]==8'd85) && !(word_data[31:2]==0);
    assign parallel_reject[94]=(word_index[7:0]==8'd94) && !(word_data[31:4]==0);
    assign parallel_reject[96]=(word_index[7:0]==8'd96) && !(word_data[31:1]==0);
    assign parallel_reject[97]=(word_index[7:0]==8'd97) && !(word_data[31:3]==0 && (!word_data[1] || word_data[0]));
    assign parallel_reject[98]=(word_index[7:0]==8'd98) && !((word_data & ~32'h0000c3ff)==0);
    assign parallel_reject[99]=(word_index[7:0]==8'd99) && !(word_data[31:11]==0);
    assign parallel_reject[100]=(word_index[7:0]==8'd100) && !((word_data & ~32'h00005fff)==0);
    assign parallel_reject[101]=(word_index[7:0]==8'd101) && !(word_data[31:16]==0);
    assign parallel_reject[120]=(word_index[7:0]==8'd120) && !(word_data[31:16]==0);
    assign parallel_reject[102]=(word_index[7:0]==8'd102) && !(word_data[31:24]==0 && word_data[23:16]<228);
    assign parallel_reject[105]=(word_index[7:0]==8'd105) && !((word_data & ~32'h01ff01ff)==0);
    assign parallel_reject[106]=(word_index[7:0]==8'd106) && !((word_data & ~32'h01ff01ff)==0);
    assign parallel_reject[107]=(word_index[7:0]==8'd107) && !((word_data & ~32'h01ff01ff)==0);
    assign parallel_reject[108]=(word_index[7:0]==8'd108) && !((word_data & ~32'h01ff01ff)==0);
    assign parallel_reject[111]=(word_index[7:0]==8'd111) && !(word_data[31:28]==0);
    assign parallel_reject[112]=(word_index[7:0]==8'd112) && !(word_data[31:28]==0);
    assign parallel_reject[115]=(word_index[7:0]==8'd115) && !(word_data[31:28]==0);
    assign parallel_reject[116]=(word_index[7:0]==8'd116) && !(word_data[31:28]==0);
    assign parallel_reject[125]=(word_index[7:0]==8'd125) && !(word_data[31:28]==0);
    assign parallel_reject[126]=(word_index[7:0]==8'd126) && !(word_data[31:28]==0);
    assign parallel_reject[119]=(word_index[7:0]==8'd119) && !((word_data & ~32'h3f3f3f3f)==0);
    assign parallel_reject[121]=(word_index[7:0]==8'd121) && !((word_data & ~32'h1f1f3fff)==0);
    assign parallel_reject[122]=(word_index[7:0]==8'd122) && !(word_data[31:5]==0);
    assign parallel_reject[123]=(word_index[7:0]==8'd123) && !(word_data[31:28]==0 && word_data[10:0]<DISPLAY_LINE_CYCLES &&
                word_data[19:11]<375 && word_data[27:20]<228 && word_data[27:20]==captured_vcount);
    assign parallel_reject[124]=(word_index[7:0]==8'd124) && !(word_data[31:4]==0);
    assign parallel_reject[127]=(word_index[7:0]==8'd127) && !((word_data & ~32'h770fff77)==0);
    assign parallel_reject[128]=(word_index[7:0]==8'd128) && !(word_data[31:1]==0);
    assign parallel_reject[129]=(word_index[7:0]==8'd129) && !(word_data[31:24]==0 && word_data[15:10]<=32 &&
                5'(word_data[9:5]-word_data[4:0])==word_data[14:10]);
    assign parallel_reject[130]=(word_index[7:0]==8'd130) && !(word_data[31:24]==0 && word_data[15:10]<=32 &&
                5'(word_data[9:5]-word_data[4:0])==word_data[14:10]);
    assign parallel_reject[147]=(word_index[7:0]==8'd147) && !((word_data & ~32'hffff007f)==0);
    assign parallel_reject[148]=(word_index[7:0]==8'd148) && !((word_data & ~32'h000047ff)==0);
    assign parallel_reject[150]=(word_index[7:0]==8'd150) && !((word_data & ~32'h000047ff)==0);
    assign parallel_reject[152]=(word_index[7:0]==8'd152) && !((word_data & ~32'h000047ff)==0);
    assign parallel_reject[149]=(word_index[7:0]==8'd149) && !(word_data[31:16]==0);
    assign parallel_reject[151]=(word_index[7:0]==8'd151) && !((word_data & ~32'he0ff00e0)==0);
    assign parallel_reject[153]=(word_index[7:0]==8'd153) && !((word_data & ~32'h0000ff3f)==0);
    assign parallel_reject[154]=(word_index[7:0]==8'd154) && !((word_data & ~32'h000040ff)==0);
    assign parallel_reject[155]=(word_index[7:0]==8'd155) && !(word_data[31:24]==0);
    assign parallel_reject[156]=(word_index[7:0]==8'd156) && !(word_data[31:27]==0 && word_data[9:1]<=64 &&
                word_data[17:14]<=8 && word_data[24:21]<=8);
    assign parallel_reject[158]=(word_index[7:0]==8'd158) && !(word_data[31:21]==0 && word_data[9:1]<=64 && word_data[17:14]<=8);
    assign parallel_reject[162]=(word_index[7:0]==8'd162) && !(word_data[31:21]==0 && word_data[9:1]<=64 && word_data[17:14]<=8);
    assign parallel_reject[160]=(word_index[7:0]==8'd160) && !(word_data[31:10]==0 && word_data[9:1]<=256);
    assign parallel_reject[157]=(word_index[7:0]==8'd157) && !(word_data[31:14]==0);
    assign parallel_reject[159]=(word_index[7:0]==8'd159) && !(word_data[31:14]==0);
    assign parallel_reject[161]=(word_index[7:0]==8'd161) && !(word_data[31:13]==0);
    assign parallel_reject[163]=(word_index[7:0]==8'd163) && !(word_data[31:23]==0);
    assign parallel_reject[164]=(word_index[7:0]==8'd164) && !(word_data[31:23]==0);
    assign parallel_reject[165]=(word_index[7:0]==8'd165) && !(word_data[31:15]==0);
    assign parallel_reject[166]=(word_index[7:0]==8'd166) && !(word_data[31:22]==0);
    assign parallel_reject[175]=(word_index[7:0]==8'd175) && !((word_data & ~32'hffff7f8b)==0);
    assign parallel_reject[176]=(word_index[7:0]==8'd176) && !((word_data & ~32'h0047c1ff)==0);
    assign parallel_reject[181]=(word_index[7:0]==8'd181) && !(word_data[31:24]==0 && word_data[5:3]<=5 &&
                word_data[11:6]<=32 && (!word_data[0] || word_data[11:6]!=0));
    assign parallel_reject[184]=(word_index[7:0]==8'd184) && !(word_data[31:12]==0);
    assign parallel_reject[185]=(word_index[7:0]==8'd185) && !(word_data[31:5]==0);
    assign parallel_reject[186]=(word_index[7:0]==8'd186) && !(word_data[31:27]==0 && word_data[2:0]<=5 &&
                word_data[7:4]<=14 && word_data[24:18]<=67 &&
                (word_data[2:0]!=2 || word_data[7:4]!=0) &&
                (word_data[2:0]!=3 || word_data[24:18]<=63));
    assign parallel_reject[189]=(word_index[7:0]==8'd189) && !(word_data<=199680 && (word_data==0 || eeprom_state==0));
    assign parallel_reject[190]=(word_index[7:0]==8'd190) && !(word_data[31:19]==0 && word_data[17:11]<56 &&
                (word_data[9] || word_data[17:11]<8));
    assign parallel_reject[191]=(word_index[7:0]==8'd191) && !(word_data[31:16]==0 && (!rtc_active ||
                (word_data[15:12]==6 && rtc_bits<(word_data[11:9]==2 ? 56 : word_data[11:9]==3 ? 24 : 8))));
    assign parallel_reject[193]=(word_index[7:0]==8'd193) && !(word_data[31:24]==0);


`ifdef GBK_GAMEPAK_PREFETCH
    assign parallel_reject[47]=0;
`endif
    assign parallel_reject[0]=0;
    assign parallel_reject[1]=0;
    assign parallel_reject[2]=0;
    assign parallel_reject[3]=0;
    assign parallel_reject[4]=0;
    assign parallel_reject[5]=0;
    assign parallel_reject[6]=0;
    assign parallel_reject[7]=0;
    assign parallel_reject[8]=0;
    assign parallel_reject[9]=0;
    assign parallel_reject[10]=0;
    assign parallel_reject[11]=0;
    assign parallel_reject[12]=0;
    assign parallel_reject[13]=0;
    assign parallel_reject[14]=0;
    assign parallel_reject[15]=0;
    assign parallel_reject[18]=0;
    assign parallel_reject[19]=0;
    assign parallel_reject[20]=0;
    assign parallel_reject[21]=0;
    assign parallel_reject[22]=0;
    assign parallel_reject[23]=0;
    assign parallel_reject[24]=0;
    assign parallel_reject[25]=0;
    assign parallel_reject[26]=0;
    assign parallel_reject[27]=0;
    assign parallel_reject[28]=0;
    assign parallel_reject[29]=0;
    assign parallel_reject[30]=0;
    assign parallel_reject[31]=0;
    assign parallel_reject[32]=0;
    assign parallel_reject[33]=0;
    assign parallel_reject[34]=0;
    assign parallel_reject[35]=0;
    assign parallel_reject[36]=0;
    assign parallel_reject[37]=0;
    assign parallel_reject[38]=0;
    assign parallel_reject[39]=0;
    assign parallel_reject[40]=0;
    assign parallel_reject[41]=0;
    assign parallel_reject[42]=0;
    assign parallel_reject[43]=0;
    assign parallel_reject[44]=0;
    assign parallel_reject[49]=0;
    assign parallel_reject[50]=0;
    assign parallel_reject[51]=0;
    assign parallel_reject[52]=0;
    assign parallel_reject[53]=0;
    assign parallel_reject[54]=0;
    assign parallel_reject[55]=0;
    assign parallel_reject[56]=0;
    assign parallel_reject[57]=0;
    assign parallel_reject[58]=0;
    assign parallel_reject[59]=0;
    assign parallel_reject[60]=0;
    assign parallel_reject[61]=0;
    assign parallel_reject[62]=0;
    assign parallel_reject[63]=0;
    assign parallel_reject[64]=0;
    assign parallel_reject[65]=0;
    assign parallel_reject[66]=0;
    assign parallel_reject[67]=0;
    assign parallel_reject[68]=0;
    assign parallel_reject[69]=0;
    assign parallel_reject[70]=0;
    assign parallel_reject[71]=0;
    assign parallel_reject[72]=0;
    assign parallel_reject[73]=0;
    assign parallel_reject[74]=0;
    assign parallel_reject[75]=0;
    assign parallel_reject[76]=0;
    assign parallel_reject[77]=0;
    assign parallel_reject[78]=0;
    assign parallel_reject[79]=0;
    assign parallel_reject[80]=0;
    assign parallel_reject[81]=0;
    assign parallel_reject[82]=0;
    assign parallel_reject[83]=0;
    assign parallel_reject[86]=0;
    assign parallel_reject[87]=0;
    assign parallel_reject[88]=0;
    assign parallel_reject[89]=0;
    assign parallel_reject[90]=0;
    assign parallel_reject[91]=0;
    assign parallel_reject[92]=0;
    assign parallel_reject[93]=0;
    assign parallel_reject[95]=0;
    assign parallel_reject[103]=0;
    assign parallel_reject[104]=0;
    assign parallel_reject[109]=0;
    assign parallel_reject[110]=0;
    assign parallel_reject[113]=0;
    assign parallel_reject[114]=0;
    assign parallel_reject[117]=0;
    assign parallel_reject[118]=0;
    assign parallel_reject[131]=0;
    assign parallel_reject[132]=0;
    assign parallel_reject[133]=0;
    assign parallel_reject[134]=0;
    assign parallel_reject[135]=0;
    assign parallel_reject[136]=0;
    assign parallel_reject[137]=0;
    assign parallel_reject[138]=0;
    assign parallel_reject[139]=0;
    assign parallel_reject[140]=0;
    assign parallel_reject[141]=0;
    assign parallel_reject[142]=0;
    assign parallel_reject[143]=0;
    assign parallel_reject[144]=0;
    assign parallel_reject[145]=0;
    assign parallel_reject[146]=0;
    assign parallel_reject[167]=0;
    assign parallel_reject[168]=0;
    assign parallel_reject[169]=0;
    assign parallel_reject[170]=0;
    assign parallel_reject[171]=0;
    assign parallel_reject[172]=0;
    assign parallel_reject[173]=0;
    assign parallel_reject[174]=0;
    assign parallel_reject[177]=0;
    assign parallel_reject[178]=0;
    assign parallel_reject[179]=0;
    assign parallel_reject[180]=0;
    assign parallel_reject[182]=0;
    assign parallel_reject[183]=0;
    assign parallel_reject[187]=0;
    assign parallel_reject[188]=0;
    assign parallel_reject[192]=0;
    assign parallel_reject[194]=0;
    assign parallel_reject[195]=0;
    assign parallel_reject[196]=0;
    assign parallel_reject[197]=0;
    assign parallel_reject[198]=0;
    assign parallel_reject[199]=0;
    assign parallel_reject[200]=0;
    assign parallel_reject[201]=0;
    assign parallel_reject[202]=0;
    assign parallel_reject[203]=0;
    assign parallel_reject[204]=0;
    assign parallel_reject[205]=0;
    assign parallel_reject[206]=0;
    assign parallel_reject[207]=0;
    assign parallel_reject_group[0]=|parallel_reject[0 +: 16];
    assign parallel_reject_group[1]=|parallel_reject[16 +: 16];
    assign parallel_reject_group[2]=|parallel_reject[32 +: 16];
    assign parallel_reject_group[3]=|parallel_reject[48 +: 16];
    assign parallel_reject_group[4]=|parallel_reject[64 +: 16];
    assign parallel_reject_group[5]=|parallel_reject[80 +: 16];
    assign parallel_reject_group[6]=|parallel_reject[96 +: 16];
    assign parallel_reject_group[7]=|parallel_reject[112 +: 16];
    assign parallel_reject_group[8]=|parallel_reject[128 +: 16];
    assign parallel_reject_group[9]=|parallel_reject[144 +: 16];
    assign parallel_reject_group[10]=|parallel_reject[160 +: 16];
    assign parallel_reject_group[11]=|parallel_reject[176 +: 16];
    assign parallel_reject_group[12]=|parallel_reject[192 +: 16];
    wire parallel_dma_ok=!(word_index>=52 && word_index<84) ||
        ((word_index[2:0]==6 || word_index[2:0]==7) ? word_data[31:28]==0 :
         word_index[2:0]==1 ? word_data[31:16]==0 :
         (word_index[2:0]==2 || word_index[2:0]==3) ? word_data==0 : 1'b1);
    wire parallel_bank_ok=!((!cpsr_fiq && word_index>=35 && word_index<40) ||
        (cpsr_fiq && word_index>=40 && word_index<45)) || word_data==0;
    always @*word_ok=word_index=={24'd0,next_word} && word_index<194 &&
        !(|parallel_reject_group) && parallel_dma_ok && parallel_bank_ok;
`else
    always @*begin
        word_ok=word_index=={24'd0,next_word} && word_index<194;
        case(word_index)
            16:word_ok=word_ok && mode_valid(word_data[4:0]);
            17:word_ok=word_ok && word_data[31:2]==0 &&
                word_data[0]==cpsr_thumb && (word_data[0] ? !pc_low[0] : pc_low==0);
            45:word_ok=word_ok && word_data<TICK_DENOMINATOR;
            46:word_ok=word_ok && word_data[31:12]==0;
`ifdef GBK_GAMEPAK_PREFETCH
            // Word 47 holds prefetch state [19:0]. Word 48 holds [45:20]:
            // next address [25:0], credit [32:26], valid [33], WAITCNT key.
            // Credit is measured in sequential service cycles (maximum 8*9).
            48:word_ok=word_ok && word_data[18:12]<=72 &&
                (word_data[19] ? (word_data[31] && word_data[11:9]<6 &&
                    word_data[18:12]<=(word_data[11:9]<2 ? (word_data[24] ? 16 : 24) :
                        word_data[11:9]<4 ? (word_data[27] ? 16 : 40) : (word_data[30] ? 16 : 72))) :
                    word_data[18:12]==0);
`else
            47:word_ok=word_ok && word_data[31:12]==0;
            48:word_ok=word_ok && word_data[31:6]==0;
`endif
            84:word_ok=word_ok && word_data[31:10]==0 && word_data[6:4]<=4 && word_data[9:7]<=4;
            85:word_ok=word_ok && word_data[31:2]==0;
            94:word_ok=word_ok && word_data[31:4]==0;
            96:word_ok=word_ok && word_data[31:1]==0;
            97:word_ok=word_ok && word_data[31:3]==0 && (!word_data[1] || word_data[0]);
            98:word_ok=word_ok && (word_data & ~32'h0000c3ff)==0;
            99:word_ok=word_ok && word_data[31:11]==0;
            100:word_ok=word_ok && (word_data & ~32'h00005fff)==0;
            101,120:word_ok=word_ok && word_data[31:16]==0;
            102:word_ok=word_ok && word_data[31:24]==0 && word_data[23:16]<228;
            105,106,107,108:word_ok=word_ok && (word_data & ~32'h01ff01ff)==0;
            111,112,115,116,125,126:word_ok=word_ok && word_data[31:28]==0;
            119:word_ok=word_ok && (word_data & ~32'h3f3f3f3f)==0;
            121:word_ok=word_ok && (word_data & ~32'h1f1f3fff)==0;
            122:word_ok=word_ok && word_data[31:5]==0;
            123:word_ok=word_ok && word_data[31:28]==0 && word_data[10:0]<DISPLAY_LINE_CYCLES &&
                word_data[19:11]<375 && word_data[27:20]<228 && word_data[27:20]==captured_vcount;
            124:word_ok=word_ok && word_data[31:4]==0;
            127:word_ok=word_ok && (word_data & ~32'h770fff77)==0;
            128:word_ok=word_ok && word_data[31:1]==0;
            129,130:word_ok=word_ok && word_data[31:24]==0 && word_data[15:10]<=32 &&
                5'(word_data[9:5]-word_data[4:0])==word_data[14:10];
            147:word_ok=word_ok && (word_data & ~32'hffff007f)==0;
            148,150,152:word_ok=word_ok && (word_data & ~32'h000047ff)==0;
            149:word_ok=word_ok && word_data[31:16]==0;
            151:word_ok=word_ok && (word_data & ~32'he0ff00e0)==0;
            153:word_ok=word_ok && (word_data & ~32'h0000ff3f)==0;
            154:word_ok=word_ok && (word_data & ~32'h000040ff)==0;
            155:word_ok=word_ok && word_data[31:24]==0;
            156:word_ok=word_ok && word_data[31:27]==0 && word_data[9:1]<=64 &&
                word_data[17:14]<=8 && word_data[24:21]<=8;
            158,162:word_ok=word_ok && word_data[31:21]==0 && word_data[9:1]<=64 && word_data[17:14]<=8;
            160:word_ok=word_ok && word_data[31:10]==0 && word_data[9:1]<=256;
            157,159:word_ok=word_ok && word_data[31:14]==0;
            161:word_ok=word_ok && word_data[31:13]==0;
            163,164:word_ok=word_ok && word_data[31:23]==0;
            165:word_ok=word_ok && word_data[31:15]==0;
            166:word_ok=word_ok && word_data[31:22]==0;
            175:word_ok=word_ok && (word_data & ~32'hffff7f8b)==0;
            176:word_ok=word_ok && (word_data & ~32'h0047c1ff)==0;
            181:word_ok=word_ok && word_data[31:24]==0 && word_data[5:3]<=5 &&
                word_data[11:6]<=32 && (!word_data[0] || word_data[11:6]!=0);
            184:word_ok=word_ok && word_data[31:12]==0;
            185:word_ok=word_ok && word_data[31:5]==0;
            186:word_ok=word_ok && word_data[31:27]==0 && word_data[2:0]<=5 &&
                word_data[7:4]<=14 && word_data[24:18]<=67 &&
                (word_data[2:0]!=2 || word_data[7:4]!=0) &&
                (word_data[2:0]!=3 || word_data[24:18]<=63);
            189:word_ok=word_ok && word_data<=199680 && (word_data==0 || eeprom_state==0);
            190:word_ok=word_ok && word_data[31:19]==0 && word_data[17:11]<56 &&
                (word_data[9] || word_data[17:11]<8);
            191:word_ok=word_ok && word_data[31:16]==0 && (!rtc_active ||
                (word_data[15:12]==6 && rtc_bits<(word_data[11:9]==2 ? 56 : word_data[11:9]==3 ? 24 : 8)));
            193:word_ok=word_ok && word_data[31:24]==0;
            default:begin end
        endcase
        if(word_index>=52 && word_index<84)case(word_index[2:0])
            // The DMA section starts at flattened word 52, not a multiple of8.
            6,7:word_ok=word_ok && word_data[31:28]==0; // programmed addresses
            1:word_ok=word_ok && word_data[31:16]==0; // reload count
            2,3:word_ok=word_ok && word_data==0; // reserved words
            default:begin end
        endcase
        if((!cpsr_fiq && word_index>=35 && word_index<40) ||
           (cpsr_fiq && word_index>=40 && word_index<45))word_ok=word_ok && word_data==0;
    end
`endif
    always @(posedge clk)begin
        if(reset || start)begin next_word<=0;pc_low<=0;cpsr_thumb<=0;cpsr_fiq<=0;captured_vcount<=0;eeprom_state<=0;rtc_bits<=0;rtc_active<=0;end
        else if(word_valid)begin
            // Saturate at the terminal word: extra input must never wrap.
            if(next_word<194)next_word<=next_word+1'b1;
            if(word_index==15)pc_low<=word_data[1:0];
            if(word_index==16)begin cpsr_thumb<=word_data[5];cpsr_fiq<=word_data[4:0]==5'h11;end
            if(word_index==102)captured_vcount<=word_data[23:16];
            if(word_index==186)eeprom_state<=word_data[2:0];
            if(word_index==190)begin rtc_bits<=word_data[17:11];rtc_active<=word_data[9];end
        end
    end
endmodule
