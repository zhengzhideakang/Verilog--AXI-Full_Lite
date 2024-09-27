/*
 * @Author: Xu XiaoKang
 * @Email: xuxiaokang_up@qq.com
 * @Date: 2021-03-11 08:34:20
 * @LastEditors: xu XiaoKang
 * @LastEditTime: 2021-04-01 08:49:15
 * @Filename:
 * @Description: file content
*/



/*
! 模块功能: 生成AXI主机接口, 完成读写时序
* 思路:
  1.
~ 时序图:

*/

module myAXI4Master
#(
  parameter TARGET_SLAVE_BASE_ADDR = 32'h1000_0000, // 目标从机基地址
  parameter TARGET_SLAVE_MAX_ADDR  = 32'h3FFF_FFFF, // 目标最大地址

  // 突发传输的数据个数, 一次突发不能跨越4kB的存储空间, 当突发类型为WRAP时，突发长度必须为2，4，8 或 16, AXI中最大为256
  parameter int BURST_LEN  = 16,
  parameter     ID_WIDTH   = 4,  // 读写线程ID的位宽1~32

  parameter int ADDR_BUS_WIDTH = 32, // 读写地址的位宽 32/64
  parameter int DATA_BUS_WIDTH = 32, // 数据总线的宽度，必须是8的倍数，32, 64, 128, 256, 512, 1024

  parameter int AWUSER_WIDTH = 1, // 用户写地址位宽 1~1024
  parameter int WUSER_WIDTH  = 1, // 用户写数据位宽 1~1024
  parameter int BUSER_WIDTH  = 1, // 用户写响应位宽 1~1024
  parameter int ARUSER_WIDTH = 1, // 用户读地址位宽 1~1024
  parameter int RUSER_WIDTH  = 1  // 用户读数据位宽 1~1024
)(
  output logic         single_burst_wr_finish, // 置高表示一次传输完成
  input  logic         wr_from_header,         // 从基地址开始写
  input  logic         rd_check_enable,
  output logic [4 : 0] error,      // 不同bit对应不同错误
  output logic         error_flag, // 为高代表有错误发生

  input  logic                        fwft_fifo_prog_full,    // 连接首字直通FIFO, 写开始信号, 高电平有效

  input  logic                        empty,
  input  logic [DATA_BUS_WIDTH-1 : 0] fwft_fifo_dout,
  output logic                        fwft_fifo_rd_en,

  //~ 写地址通道
  output logic [ID_WIDTH-1 : 0]          m_axi_awid,     // 写地址ID
  output logic [ADDR_BUS_WIDTH-1 : 0]    m_axi_awaddr,   // 写地址
  output logic [7 : 0]                   m_axi_awlen,    // 一次写的数据长度
  output logic [2 : 0]                   m_axi_awsize,   // 一个时钟节拍所传输的数据位数,
  output logic [1 : 0]                   m_axi_awburst,  // 确定如何计算突发中每次传输的地址
  output logic                           m_axi_awlock,   // 锁类型。提供有关转移的原子特性的其他信息
  output logic [3 : 0]                   m_axi_awcache,  // 内存类型。该信号指示如何通过系统进行交易
  output logic [2 : 0]                   m_axi_awprot,   // 保护类型
  output logic [3 : 0]                   m_axi_awqos,    // 服务质量，为每个写入事务发送的QoS标识符
  output logic [3 : 0]                   m_axi_awregion, // 事物区域指示器 4'b0000
  output logic [AWUSER_WIDTH-1 : 0]      m_axi_awuser,   // 可选写地址通道的用户自定义信号
  output logic                           m_axi_awvalid,
  input  logic                           m_axi_awready,

  //~ 写数据通道
  output logic [DATA_BUS_WIDTH-1 : 0]    m_axi_wdata, // 写数据通道
  output logic [DATA_BUS_WIDTH/8-1 : 0]  m_axi_wstrb, // 写数据有效字节位
  output logic                           m_axi_wlast, // 指示写数据的最后一位
  output logic [WUSER_WIDTH-1 : 0]       m_axi_wuser, // 可选写数据通道的用户自定义信号
  output logic                           m_axi_wvalid,
  input  logic                           m_axi_wready,

  //~ 写响应通道
  input  logic [ID_WIDTH-1 : 0]          m_axi_bid,
  input  logic [1 : 0]                   m_axi_bresp, // 写响应
  input  logic [BUSER_WIDTH-1 : 0]       m_axi_buser, // 可选写响应通道的用户自定义信号
  input  logic                           m_axi_bvalid,
  output logic                           m_axi_bready,

  //~ 读地址通道
  output logic [ID_WIDTH-1 : 0]          m_axi_arid,     // 读地址ID
  output logic [ADDR_BUS_WIDTH-1 : 0]    m_axi_araddr,   // 读地址
  output logic [7 : 0]                   m_axi_arlen,    // 一次burst中的确定传输次数
  output logic [2 : 0]                   m_axi_arsize,   // 每次传输的数据size
  output logic [1 : 0]                   m_axi_arburst,  // 决定了burst中的每次传输的地址如何计算
  output logic                           m_axi_arlock,   // 锁类型
  output logic [3 : 0]                   m_axi_arcache,
  output logic [2 : 0]                   m_axi_arprot,   // 保护类型
  output logic [3 : 0]                   m_axi_arqos,    // Quality of Service
  output logic [3 : 0]                   m_axi_arregion, // 事物区域指示器 4'b0000
  output logic [ARUSER_WIDTH-1 : 0]      m_axi_aruser,   // 可选读地址通道的用户自定义信号
  output logic                           m_axi_arvalid,
  input  logic                           m_axi_arready,

  //~ 读数据通道
  input  logic [ID_WIDTH-1 : 0]          m_axi_rid,   // 读数据ID
  input  logic [DATA_BUS_WIDTH-1 : 0]    m_axi_rdata, // 读数据
  input  logic [1 : 0]                   m_axi_rresp, // 读响应
  input  logic                           m_axi_rlast, // 指示读数据的最后一位
  input  logic [RUSER_WIDTH-1 : 0]       m_axi_ruser, // 可选读数据通道的用户自定义信号
  input  logic                           m_axi_rvalid,
  output logic                           m_axi_rready,

  input  logic         m_axi_aresetn, // 复位
  input  logic         m_axi_aclk     // 接口时钟
);


//> 多信号同步，检测上升沿 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic fwft_fifo_prog_full_r1;
logic fwft_fifo_prog_full_r2;
always_ff @(posedge m_axi_aclk) begin
    if (~m_axi_aresetn) begin
      fwft_fifo_prog_full_r1 <= 1'b0;
      fwft_fifo_prog_full_r2 <= 1'b0;
    end
    else begin
      fwft_fifo_prog_full_r1 <= fwft_fifo_prog_full;
      fwft_fifo_prog_full_r2 <= fwft_fifo_prog_full_r1;
    end
end


logic wr_from_header_r1;
logic wr_from_header_r2;
always_ff @(posedge m_axi_aclk) begin
    if (~m_axi_aresetn) begin
      wr_from_header_r1 <= 1'b0;
      wr_from_header_r2 <= 1'b0;
    end
    else begin
      wr_from_header_r1 <= wr_from_header;
      wr_from_header_r2 <= wr_from_header_r1;
    end
end

logic wr_from_header_pedge;
always_comb begin
  wr_from_header_pedge = ~(wr_from_header_r2) && wr_from_header_r1;
end


logic go2header_en;
logic go2header; // 接收从头开始写的信号, 在读写空闲时间内使其有效
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    go2header_en <= 1'b0;
  else if (wr_from_header_pedge)
    go2header_en <= 1'b1;
  else if (go2header)
    go2header_en <= 1'b0;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    go2header <= 1'b0;
  else if (go2header_en && single_burst_wr_finish)
    go2header <= 1'b1;
  else
    go2header <= 1'b0;
end


logic start_single_burst_write; // 开始单次突发写
logic burst_write_active; // 正在写
logic bnext;
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    burst_write_active <= 1'b0;
  else if (start_single_burst_write)
    burst_write_active <= 1'b1;
  else if (bnext)
    burst_write_active <= 0;
  else
    burst_write_active <= burst_write_active;
end


logic burst_read_active; // 正在读指示信号
always_comb begin
  if (~m_axi_aresetn)
    start_single_burst_write <= 1'b0;
  else if (~empty && fwft_fifo_prog_full_r2 && ~burst_write_active && ~burst_read_active)
    start_single_burst_write <= 1'b1;
  else
    start_single_burst_write <= 1'b0;
end


logic start_single_burst_write_r1;
logic start_single_burst_write_r2;
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn) begin
    start_single_burst_write_r1 <= 1'b0;
    start_single_burst_write_r2 <= 1'b0;
  end
    start_single_burst_write_r1 <= start_single_burst_write;
    start_single_burst_write_r2 <= start_single_burst_write_r1;
end


logic start_single_burst_write_pedge;
always_comb begin
  start_single_burst_write_pedge = (~start_single_burst_write_r2) && start_single_burst_write_r1;
end
//> 多信号同步，检测上升沿 ------------------------------------------------------------



//< write_address 写地址 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic awnext;
always_comb begin
  awnext = m_axi_awvalid && m_axi_awready;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_awid <= '0;
  else if (bnext)
    m_axi_awid <= m_axi_awid + 1'b1;
  else
    m_axi_awid <= m_axi_awid;
end


// 生成写地址有效信号
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_awvalid <= 1'b0;
  else if (start_single_burst_write_pedge) // 传输开始后，马上写地址
    m_axi_awvalid <= 1'b1;
  else if (awnext) // 一次突发中，写地址只需要传一次
    m_axi_awvalid <= 1'b0;
  else
    m_axi_awvalid <= m_axi_awvalid;
end


logic [ADDR_BUS_WIDTH-1 : 0] 	axi_awaddr; // 偏移地址
always_ff @(posedge m_axi_aclk) begin
  // 复位，地址超过最大地址，或者收到外部从头开始写的信号，偏移地址置0
  if (~m_axi_aresetn || go2header) // 从头开始写信号, 必须在读写空闲时有效, 在读写过程中变地址可能造成错乱
    axi_awaddr <= '0;
  else if (single_burst_wr_finish) // 注意, 写读地址共用一个, 必须等两个地址都生效后, 才能变地址
    if (axi_awaddr > (TARGET_SLAVE_MAX_ADDR - TARGET_SLAVE_BASE_ADDR) - (BURST_LEN * DATA_BUS_WIDTH/8)) // 再加一次就越界了, 所以置0
    axi_awaddr <= '0;
    else // 一次突发写完成后, 地址增加
      axi_awaddr <= axi_awaddr + (BURST_LEN * DATA_BUS_WIDTH/8);
  else
    axi_awaddr <= axi_awaddr;
end


always_comb begin
  m_axi_awaddr = TARGET_SLAVE_BASE_ADDR + axi_awaddr; // 实际地址 = 基地址 + 偏移地址
  m_axi_awburst = 2'b01; // INCR，自增突发类型
  m_axi_awlen = BURST_LEN - 1; // Burst长度 = 传输长度 - 1
  m_axi_awsize = $clog2(DATA_BUS_WIDTH / 8 - 1);
  m_axi_awlock = '0;
  m_axi_awcache = 4'b0010; // Update value to 4'b0011 if coherent accesses to be used via the Zynq ACP port. Not Allocated, Modifiable, not Bufferable. Not Bufferable since this example is meant to test memory, not intermediate cache.
  m_axi_awprot = '0;
  m_axi_awqos = '0;
  m_axi_awregion = '0;
  m_axi_awuser = '0; // 表示1, 而'1表示所有位全为1
end
//< write_address 写地址 ------------------------------------------------------------



//> write_data 写数据 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic wnext;
always_comb begin
  wnext = m_axi_wvalid && m_axi_wready;
end


logic [$clog2(BURST_LEN)-1 : 0] write_cnt;
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || bnext) // 写完成后，计数置0
    write_cnt <= '0;
  else if (wnext)
    write_cnt <= write_cnt + 1;
  else
    write_cnt <= write_cnt;
end


logic [DATA_BUS_WIDTH-1 : 0] wdata_array [BURST_LEN]; // 存放写入的数据，最大空间为一次突发的最大数据量4kB
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn) // 开始写后，写计数置0
    wdata_array <= '{default : '0};
  else if (wnext)
    wdata_array[write_cnt] = m_axi_wdata;
  else
    wdata_array <= wdata_array;
end


always_comb begin
  if (~m_axi_aresetn) // 开始写后，写计数置0
    fwft_fifo_rd_en = '0;
  else if (wnext) // 需要一个数据读使能就使能一次
    fwft_fifo_rd_en = 1'b1;
  else
    fwft_fifo_rd_en = '0;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_wvalid <= 1'b0;
  else if (wnext && m_axi_wlast) // 最后一个数据，不再继续有效了
    m_axi_wvalid <= 1'b0;
  else if (start_single_burst_write_pedge) // 数据有效就可以传输了，各通道相互独立
    m_axi_wvalid <= 1'b1;
  else
    m_axi_wvalid <= m_axi_wvalid;
end


always_comb begin
  if (~m_axi_aresetn)
    m_axi_wdata <= '0;
  else
    m_axi_wdata <= fwft_fifo_dout;
end


always_ff @(posedge m_axi_aclk) begin // 写数据的最后一位
  if (~m_axi_aresetn)
    m_axi_wlast <= 1'b0;
  else if (((write_cnt == BURST_LEN-2 && write_cnt >= 2) && wnext) || (BURST_LEN == 1 ))
    m_axi_wlast <= 1'b1;
  else
    m_axi_wlast <= 1'b0;
end


always_comb begin
  m_axi_wstrb = '1; // 所有数据位均有效
  m_axi_wuser = '0;
end
//> write_data 写数据 ------------------------------------------------------------



//< write_response 写响应 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
always_comb begin
  bnext = m_axi_bvalid && m_axi_bready;
end

always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_bready <= '0;
  else if (m_axi_wlast && wnext) // 数据传完后置1
    m_axi_bready <= 1'b1;
  else if (bnext) // 接收响应后置0
    m_axi_bready <= 1'b0;
  else
    m_axi_bready <= m_axi_bready;
end


logic awid_notequal_bid; // 写地址ID和写响应ID不一致报错
always_comb begin
  if (bnext && m_axi_bid != m_axi_awid)
    awid_notequal_bid = 1'b1;
  else
    awid_notequal_bid = 1'b0;
end


enum logic [1:0] {OKEY   = 2'b00,
                  EXOKEY = 2'b01,
                  SLVERR = 2'b10,
                  DECERR = 2'b11} RESP; // 枚举写/读响应, 共四种

logic write_resp_error;
always_comb begin
  if (bnext && (m_axi_bresp == SLVERR) || (m_axi_bresp == DECERR)) // 接收写响应报错
    write_resp_error = 1'b1;
  else
    write_resp_error = 1'b0;
end
//< write_response 写响应 ------------------------------------------------------------



//> read_address 读地址 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic arnext;
always_comb begin
  arnext = m_axi_arready && m_axi_arvalid;
end


logic rdone; // 读完成
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_arid <= '0;
  else if (rdone)
    m_axi_arid <= m_axi_arid + 1'b1;
  else
    m_axi_arid <= m_axi_arid;
end


logic start_single_burst_read;  // 读开始
always_comb begin
  start_single_burst_read = rd_check_enable && bnext && (~burst_read_active); // 写完成后, 没有在读，读开始
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_arvalid <= 1'b0;
  else if (start_single_burst_read)
    m_axi_arvalid <= 1'b1;
  else if (arnext) // 一次突发读中，读地址只需传一次
    m_axi_arvalid <= 1'b0;
  else
    m_axi_arvalid <= m_axi_arvalid;
end


always_comb begin
  // m_axi_araddr = TARGET_SLAVE_BASE_ADDR + axi_araddr;
  m_axi_araddr = m_axi_awaddr;
  m_axi_arlen = BURST_LEN - 1;
  m_axi_arsize = $clog2(DATA_BUS_WIDTH / 8 - 1);
  m_axi_arburst = 2'b01;
  m_axi_arlock = '0;
  m_axi_arcache = 4'b0010; // Update value to 4'b0011 if coherent accesses to be used via the Zynq ACP port. Not Allocated, Modifiable, not Bufferable. Not Bufferable since this example is meant to test memory, not intermediate cache.
  m_axi_arprot = '0;
  m_axi_arqos = '0;
  m_axi_arregion = '0;
  m_axi_aruser = '0;
end
//> read_address 读地址 ------------------------------------------------------------



//< read_data 读数据 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic rnext;
always_comb begin
  rnext = m_axi_rvalid && m_axi_rready;
end


always_ff @(posedge m_axi_aclk) begin // 正在读
  if (~m_axi_aresetn)
    burst_read_active <= 1'b0;
  else if (start_single_burst_read)
    burst_read_active <= 1'b1;
  else if (rnext && m_axi_rlast)
    burst_read_active <= 0;
  else
    burst_read_active <= burst_read_active;
end


always_comb begin // 读完成
  rdone = m_axi_rlast && rnext;
end


// 指示一次先写后读得传输完成
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    single_burst_wr_finish <= '0;
  else if (rd_check_enable)
    single_burst_wr_finish = rdone;
  else
    single_burst_wr_finish = bnext;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_rready <= 1'b0;
  else if (start_single_burst_read) // 读地址传完后，读数据ready置高
    m_axi_rready <= 1'b1;
  else if (rdone) // 最后一个数据读完后，读数据ready置低
    m_axi_rready <= 1'b0;
  else
    m_axi_rready <= m_axi_rready;
end


logic [$clog2(BURST_LEN)-1 : 0] read_cnt;  // 一次传输读计数
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || single_burst_wr_finish)
    read_cnt <= 0;
  else if (rnext)
    read_cnt <= read_cnt + 1;
  else
    read_cnt <= read_cnt;
end


logic rid_notequal_arid; // 读数据ID不等于读地址ID
always_comb begin
  if (rnext && (m_axi_arid != m_axi_rid))
    rid_notequal_arid = 1'b1;
  else
    rid_notequal_arid = 1'b0;
end


logic rdata_notequal_wdata; // 读数据不等于写数据
always_comb begin
  if (rnext && (m_axi_rdata != wdata_array[read_cnt]))
    rdata_notequal_wdata = 1'b1;
  else
    rdata_notequal_wdata = 1'b0;
end


logic read_resp_error; // 读响应报错
always_comb begin
  if (rnext && (m_axi_rresp == SLVERR) || (m_axi_rresp == DECERR))
    read_resp_error = 1'b1;
  else
    read_resp_error = 1'b0;
end


always_comb begin
  error = { awid_notequal_bid,
            write_resp_error,
            rid_notequal_arid,
            rdata_notequal_wdata,
            read_resp_error};
end


always_comb begin
  error_flag = (|error); // 缩位运算符，每一位或，得到一位数据, 指示出现了错误
end
//< read_data 读数据 ------------------------------------------------------------



endmodule