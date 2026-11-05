`timescale 1ns/1ps
module gba_playtime_clock_tb;
 wire snapshot_ready=1; wire [97:0] rtc_snapshot=0; wire [97:0] loaded_rtc; wire load_rtc,export_busy;
 reg clk=0,new_game=0,playing=0,host_toggle=0,host_valid=0;
 reg [31:0] host_time_bcd=0;
 wire wall_valid;
 wire [23:0] wall_time_bcd;
 wire [31:0] session_seconds,total_seconds,loaded_total,read_data;
 wire load_total,export_locked,import_valid;
 reg [127:0] game_id=128'h112233445566778899aabbccddeeff00;
 reg load_write=0,export_request=0,allcomplete=0,read_strobe=0,endian_little=1;
 reg [2:0] load_index=0,read_index=0;
 reg [31:0] load_data=0;
 always #5 clk=~clk;
 gba_playtime_clock #(.CLOCK_HZ(10)) clock_dut(.clk,.new_game,.playing,.host_toggle,.host_valid,.host_time_bcd,
  .load_total,.loaded_total,.wall_valid,.wall_time_bcd,.session_seconds,.total_seconds);
 gba_playtime_record record(.clk,.new_game,.playing,.game_id,.total_seconds,.load_write,.load_index,.load_data,
  .export_request,.allcomplete,.read_strobe,.read_index,.endian_little,.snapshot_ready,.rtc_snapshot,
  .export_locked,.load_total,.loaded_total,.read_data,.import_valid,
  .identity_write(1'b0),.identity_ready(1'b1),.identity_index(2'd0),.identity_data(32'd0),
  .load_word_read(1'b0),.load_word_index(2'd0));
 task tick;@(posedge clk);#1;endtask
 task new_session;
  @(negedge clk);new_game=1;tick();@(negedge clk);new_game=0;tick();
 endtask
 reg [31:0] words[0:7];
 task load_record(input bit wrong_id,corrupt);
  words[0]=32'h54504247;words[1]=1;
  for(integer n=0;n<4;n=n+1)words[2+n]=game_id[n*32+:32];
  if(wrong_id)words[3]=words[3]^1;
  words[6]=12345;words[7]=0;
  for(integer n=0;n<7;n=n+1)words[7]=words[7]^words[n];
  if(corrupt)words[7]=words[7]^1;
  for(integer n=0;n<8;n=n+1)begin
   @(negedge clk);load_write=1;load_index=n;load_data=words[n];tick();
  end
  @(negedge clk);load_write=0;repeat(2)tick();
 endtask
 integer before_session,before_total;
 reg [23:0] before_wall;
 reg [127:0] frozen_id_expected;
 initial begin
  new_session();load_record(1,0);if(import_valid || total_seconds!=0)$fatal(1,"Other game's stats were imported");
  load_record(0,1);if(import_valid || total_seconds!=0)$fatal(1,"Corrupt stats were imported");
  load_record(0,0);if(!import_valid || total_seconds!=12345)$fatal(1,"Valid stats failed import");
  @(negedge clk);host_valid=1;host_time_bcd=32'h00235959;host_toggle=1;tick();
  repeat(10)tick();if(wall_time_bcd!=0 || !wall_valid)$fatal(1,"Wall-clock midnight rollover failed");
  @(negedge clk);playing=1;repeat(25)tick();
  if(session_seconds!=2 || total_seconds!=12347)$fatal(1,"Playtime count wrong");
  @(negedge clk);playing=0;before_session=session_seconds;before_total=total_seconds;before_wall=wall_time_bcd;
  repeat(25)tick();if(session_seconds!=before_session || total_seconds!=before_total || wall_time_bcd==before_wall)
   $fatal(1,"Paused playtime affected wall clock or lost fractional seconds");
  @(negedge clk);playing=1;repeat(5)tick();if(session_seconds!=3)$fatal(1,"Fractional playtime was lost on pause");
  frozen_id_expected=game_id;
  @(negedge clk);export_request=1;tick();@(negedge clk);export_request=0;
  before_total=total_seconds;repeat(22)tick();
  read_index=6;read_strobe=1;tick();if(read_data!=before_total)$fatal(1,"Live playtime tore export snapshot");
  game_id=~game_id;
  for(integer n=0;n<4;n=n+1)begin
   read_index=n+2;tick();if(read_data!==frozen_id_expected[n*32+:32])$fatal(1,"Live game identity tore export snapshot");
  end
  read_strobe=0;load_record(0,0);if(total_seconds<=before_total)$fatal(1,"Late import rolled back active totals");
  @(negedge clk);playing=0;allcomplete=1;tick();@(negedge clk);allcomplete=0;
  if(export_locked)$fatal(1,"Stats export lock stuck");
  new_session();if(session_seconds!=0 || total_seconds!=0)$fatal(1,"New game retained previous totals");
  if(!wall_valid)$fatal(1,"New game reset wall-clock time");
  // No record existed at launch. A valid file arriving after play has begun
  // must remain rejected even after returning to the Pocket menu.
  @(negedge clk);playing=1;repeat(20)tick();@(negedge clk);playing=0;
  before_total=total_seconds;load_record(0,0);
  if(import_valid || total_seconds!=before_total)$fatal(1,"Late first import after play rolled totals backwards");
  $display("PASS: independent wall/session/total clocks, pause fractions, per-game stats import isolation, corruption rejection and coherent export");$finish;
 end
 initial begin #100000;$fatal(1,"Playtime timeout");end
endmodule
