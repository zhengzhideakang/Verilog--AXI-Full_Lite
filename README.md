# Verilog功能模块--AXI4-Full_Lite

Gitee与Github同步：

[Verilog功能模块--AXI-Full_Lite: Verilog功能模块--AXI4-Full Verilog功能模块--AXI4-Lite (gitee.com)](https://gitee.com/xuxiaokang/verilog-functional-module--AXI4-Full_Lite)

[zhengzhideakang/Verilog--AXI-Full_Lite: Verilog功能模块--AXI4-Full，AXI4-Lite (github.com)](https://github.com/zhengzhideakang/Verilog--AXI-Full_Lite)

## 简介

这是3、4年轻写的AXI主机模块，当时还喜欢用SystemVerilog，几个模块功能都是实现对DDR的读写，测试的芯片为ZYNQ 7020，功能测试均无问题。

模块均为标准的AXI接口，可在Vivado中对模块进行IP封装，之后在Block Design可以直接与其它AXI接口IP进行总线连接。

关于这些模块的仿真/测试工程请参考我的CSDN博客：[徐晓康的博客-CSDN博客](https://blog.csdn.net/weixin_42837669?spm=1011.2415.3001.5343)，搜索AXI。

## 模块框图

### myAxi3Master

<img src="https://picgo-dakang.oss-cn-hangzhou.aliyuncs.com/img/myAxi3Master.svg" alt="myAxi3Master" />

### myAXI4LiteMaster

<img src="https://picgo-dakang.oss-cn-hangzhou.aliyuncs.com/img/myAXI4LiteMaster.svg" alt="myAXI4LiteMaster" />

### myAXI4Master

<img src="https://picgo-dakang.oss-cn-hangzhou.aliyuncs.com/img/myAXI4Master.svg" alt="myAXI4Master" />
