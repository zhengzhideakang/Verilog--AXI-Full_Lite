/*
 * @Author       : Xu Dakang
 * @Email        : XudaKang_up@qq.com
 * @Date         : 2021-05-08 20:46:49
 * @LastEditors  : Xu Xiaokang
 * @LastEditTime : 2024-09-27 15:35:45
 * @Filename     : myAXI4LiteMaster.sv
 * @Description  : AXI4-Lite协议主机
*/

/*
! 模块功能: AXI4-Lite协议主机，从FWFT FIFO中读取数据，写入到一段地址中。
* 注意:
  1.此模块需要配合FWFT FIFO使用，这里采用FIFO的empty的取反信号作为写操作启动信号，意味着FIFO中一有数据就启动写，
    可以根据实际需要（如需要缓冲），将FIFO的其它输出信号作为启动信号。
  2.必须保证：此协议主机对数据的写入数据 ≥ 数据写入FIFO的速度，否则，FIFO将慢慢FULL，后续的数据会被丢弃。
  3.必须保证：FIFO的读时钟rd_clk与此模块的m_axi_aclk为同一个时钟，这是为了保证此模块对FIFO的读取操作正常。
  4.对一个新的存储器件进行写操作时，可先使能RD_CHECK_EN，这时写操作完成后会启动读操作，
    从同一地址读出数据并与写入数据比较，以验证器件的写入与读出功能是否都正常
  5.RD_CHECK_EN仅用于验证器件的写入/读出功能，验证没问题后，应关闭RD_CHECK_EN，减小不必要的资源消耗
  6.注意error与error_flag信号，本模块未设置错误重传机制，这两个信号仅用于调试中观察错误是否发生，
    正常来说，这两个信号应始终为全0。
  7.注意single_burst_wr_finish仅表示单次写完成，而不是读写完成，
    正常来说读写是独立的，可以在前一次读操作还在进行时就启动下一次的写操作，这使得模块读写性能更高。
  8.本模块采用了低电平有效的同步复位方式，复位信号m_axi_aresetn低电平应至少持续两个时钟周期，
    以保证所有中间信号与输出信号被有效复位。
  9.给所有时序逻辑加复位并不会额外消耗资源，应为Filp-Flop本就带有复位端，不用也是闲着。
    所以，应该给所有时序逻辑加上复位，组合逻辑看情况加不加复位，如果组合逻辑的值受时序逻辑的输出控制，可不加复位。
*/

module myAXI4LiteMaster
#(
  parameter TARGET_SLAVE_BASE_ADDR = 32'h1000_0000, // 目标从机基地址
  parameter TARGET_SLAVE_MAX_ADDR  = 32'h3FFF_FFFF, // 目标从机最大地址

  parameter ADDR_WIDTH = 32, // 读写地址的位宽, 可选32/64
  parameter DATA_WIDTH = 32, // 数据总线的宽度, 可选32/64

  parameter RD_CHECK_EN = 0 // 读检查使能
)(
  output logic                       single_burst_wr_finish, // 单次写完成

  output logic [2 : 0]               error,      // 不同bit对应不同错误
  output logic                       error_flag, // 为高代表有错误发生

  // FWFT FIFO读接口
  input  logic                       fwft_fifo_empty,
  input  logic [DATA_WIDTH-1 : 0]    fwft_fifo_dout,
  output logic                       fwft_fifo_rd_en,


  //~ 写地址通道
  output logic [ADDR_WIDTH-1 : 0]    m_axi_awaddr,  // 写地址
  output logic [2 : 0]               m_axi_awprot,  // 写保护
  output logic                       m_axi_awvalid,
  input  logic                       m_axi_awready,

  //~ 写数据通道
  output logic [DATA_WIDTH-1 : 0]    m_axi_wdata,   // 写数据通道
  output logic [DATA_WIDTH/8-1 : 0]  m_axi_wstrb,   // 写数据有效字节位
  output logic                       m_axi_wvalid,
  input  logic                       m_axi_wready,

  //~ 写响应通道
  input  logic [1 : 0]               m_axi_bresp,   // 写响应
  input  logic                       m_axi_bvalid,
  output logic                       m_axi_bready,

  //~ 读地址通道
  output logic [ADDR_WIDTH-1 : 0]    m_axi_araddr,  // 读地址
  output logic [2 : 0]               m_axi_arprot,  // 读保护
  output logic                       m_axi_arvalid,
  input  logic                       m_axi_arready,

  //~ 读数据通道
  input  logic [DATA_WIDTH-1 : 0]    m_axi_rdata,   // 读数据
  input  logic [1 : 0]               m_axi_rresp,   // 读响应
  input  logic                       m_axi_rvalid,
  output logic                       m_axi_rready,

  input  logic  m_axi_aclk,
  input  logic  m_axi_aresetn
);



//> 写开始与写完成 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic start;
always_comb begin
  start = ~fwft_fifo_empty; // fifo有数据就开始写
end


logic start_r1;
logic start_r2;
always_ff @(posedge m_axi_aclk) begin
  start_r1 <= start;
  start_r2 <= start_r1;
end


logic bnext;
always_comb begin
  single_burst_wr_finish = bnext; // 写响应意味着单次写完成
end


logic start_single_burst_write; // 开始单次突发写
logic burst_write_active;       // 正在写
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    burst_write_active <= 1'b0;
  else if (start_single_burst_write)
    burst_write_active <= 1'b1;
  else if (single_burst_wr_finish)
    burst_write_active <= 0;
  else
    burst_write_active <= burst_write_active;
end


always_comb begin
  if (start_r2 && ~burst_write_active) // start有效且不正在写时，开始写
    start_single_burst_write = 1'b1;
  else
    start_single_burst_write = 1'b0;
end
//> 写开始与写完成 ------------------------------------------------------------



//< write_address 写地址 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic awnext;
always_comb begin
  awnext = m_axi_awvalid && m_axi_awready;
end


// 生成写地址有效信号
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_awvalid <= 1'b0;
  else if (start_single_burst_write) // 传输开始后，马上写地址
    m_axi_awvalid <= 1'b1;
  else if (awnext) // 一次突发中，写地址只需要传一次
    m_axi_awvalid <= 1'b0;
  else
    m_axi_awvalid <= m_axi_awvalid;
end


logic [ADDR_WIDTH-1 : 0] 	axi_awaddr; // 偏移地址
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    axi_awaddr <= '0;
  else if (start_single_burst_write)
    /*
    * 对于地址（0000~FFFF）数据位宽32的传输，地址变化如下：
    * 0000 -> 0004 -> 0008 -> ... -> FFF8 -> FFFC -> 10000(超过范围)
    * 末地址为 FFFC = FFFF + 1 - 32/8
    */
    if (TARGET_SLAVE_BASE_ADDR + DATA_WIDTH/8 + axi_awaddr <= TARGET_SLAVE_MAX_ADDR + 1 - DATA_WIDTH/8)
      axi_awaddr <= axi_awaddr + DATA_WIDTH/8; // 一次突发写完成后, 地址增加
    else
      axi_awaddr <= '0;
  else
    axi_awaddr <= axi_awaddr;
end


always_comb begin
  m_axi_awaddr = TARGET_SLAVE_BASE_ADDR + axi_awaddr; // 实际地址 = 基地址 + 偏移地址
  m_axi_awprot = '0;
end
//< write_address 写地址 ------------------------------------------------------------



//> write_data 写数据 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic wnext;
always_comb begin
  wnext = m_axi_wvalid && m_axi_wready;
end


always_comb begin
  fwft_fifo_rd_en = wnext; // 写入一个数据，FIFO就读出这个数据
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_wvalid <= 1'b0;
  else if (start_single_burst_write)
    m_axi_wvalid <= 1'b1;
  else if (wnext)
    m_axi_wvalid <= 1'b0;
  else
    m_axi_wvalid <= m_axi_wvalid;
end


always_comb begin
  m_axi_wstrb = '1; // 所有数据位均有效
  m_axi_wdata = fwft_fifo_dout;
end
//> write_data 写数据 ------------------------------------------------------------



//< write_response 写响应 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
always_comb begin
  bnext = m_axi_bvalid && m_axi_bready;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    m_axi_bready <= 1'b0;
  else if (wnext) // 数据传完后置1
    m_axi_bready <= 1'b1;
  else if (bnext) // 接收响应后置0
    m_axi_bready <= 1'b0;
  else
    m_axi_bready <= m_axi_bready;
end


logic write_resp_error;
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn)
    write_resp_error <= 1'b0;
  if (bnext && (m_axi_bresp[1] == 1'b1)) // 接收写响应报错
    write_resp_error <= 1'b1;
  else
    write_resp_error <= 1'b0;
end
//< write_response 写响应 ------------------------------------------------------------



//> 读开始 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic start_single_burst_read; // 读开始
logic burst_read_active;       // 正在读
logic rnext;                   // 读数据信号，也意味着单次读完成
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    burst_read_active <= 1'b0;
  else if (start_single_burst_read)
    burst_read_active <= 1'b1;
  else if (rnext)
    burst_read_active <= 1'b0;
  else
    burst_read_active <= burst_read_active;
end


always_comb begin
  // 当读使能有效，且写响应完成，且不是正在读时，开始读
  if (RD_CHECK_EN && bnext && ~burst_read_active)
    start_single_burst_read = 1'b1;
  else
    start_single_burst_read = 1'b0;
end
//> 读开始 ------------------------------------------------------------



//< read_address 读地址 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
logic arnext;
always_comb begin
  arnext = m_axi_arready && m_axi_arvalid;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    m_axi_arvalid <= 1'b0;
  else if (start_single_burst_read)
    m_axi_arvalid <= 1'b1;
  else if (arnext) // 一次突发读中，读地址只需传一次
    m_axi_arvalid <= 1'b0;
  else
    m_axi_arvalid <= m_axi_arvalid;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    m_axi_araddr <= '0;
  else if (start_single_burst_read)
    m_axi_araddr <= m_axi_awaddr;
  else
    m_axi_araddr <= m_axi_araddr;
end


always_comb begin
  m_axi_arprot = '0;
end
//< read_address 读地址 ------------------------------------------------------------



//> read_data 读数据 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
always_comb begin
  rnext = m_axi_rvalid && m_axi_rready;
end


always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    m_axi_rready <= 1'b0;
  else if (start_single_burst_read) // 读开始，读数据ready置高
    m_axi_rready <= 1'b1;
  else if (rnext) // 一个数据读完后，读数据ready置低
    m_axi_rready <= 1'b0;
  else
    m_axi_rready <= m_axi_rready;
end


logic wnext_cnt;
always_ff @(posedge m_axi_aclk) begin // 写数据计数
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    wnext_cnt <= 1'b0;
  else if (wnext)
    wnext_cnt <= wnext_cnt + 1'b1;
  else
    wnext_cnt <= wnext_cnt;
end


logic [DATA_WIDTH-1 : 0] this_two_wdata [2]; // 暂存两个写入的数据
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    this_two_wdata <= '{default : '0};
  else if (wnext)
    this_two_wdata[wnext_cnt] <= m_axi_wdata;
  else
    this_two_wdata <= this_two_wdata;
end


logic rnext_cnt;
always_ff @(posedge m_axi_aclk) begin // 读数据计数
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    rnext_cnt <= 1'b0;
  else if (rnext)
    rnext_cnt <= rnext_cnt + 1'b1;
  else
    rnext_cnt <= rnext_cnt;
end


logic rdata_notequal_wdata; // 读数据不等于写数据
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    rdata_notequal_wdata <= 1'b0;
  if (rnext && (m_axi_rdata != this_two_wdata[rnext_cnt]))
    rdata_notequal_wdata <= 1'b1;
  else
    rdata_notequal_wdata <= 1'b0;
end


logic read_resp_error; // 读响应报错
always_ff @(posedge m_axi_aclk) begin
  if (~m_axi_aresetn || ~RD_CHECK_EN)
    read_resp_error <= 1'b0;
  if (rnext && (m_axi_rresp[1] == 1'b1))
    read_resp_error <= 1'b1;
  else
    read_resp_error <= 1'b0;
end


always_comb begin
  error = { write_resp_error,
            rdata_notequal_wdata,
            read_resp_error};
end


always_comb begin
  error_flag = (|error); // 缩位运算符，每一位或，得到一位数据, 指示是否出现错误
end
//> read_data 读数据 ------------------------------------------------------------



endmodule