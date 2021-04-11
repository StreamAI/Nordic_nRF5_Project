# 如何抓包分析BLE 空口报文（GAP + GATT + LESC procedure）？

@[TOC]

> 前篇博文介绍了[如何调试嵌入式代码？](https://blog.csdn.net/m0_37621078/article/details/114918430) 但对于通讯协议，我们要了解通讯过程的详细信息，需要获取通讯过程中交互的报文以及时间，如何抓取通讯报文呢？如何解析抓取到的报文呢？

# 一、如何抓取BLE 空口报文？

我们最常使用的以太网抓包工具有wireshark 和tcpdump，前者提供可视化界面，方便直观了解报文格式，后者侧重命令行工具，方便通过自动化脚本抓包。这些抓包工具可以抓取BLE / Wi-Fi 这类无线通讯协议报文吗？

对于以太网这类有线通讯协议，数据包的传送分发主要是通过路由器和交换机完成的，路由器和交换机分发数据包主要是靠维护的路由表和MAC 地址表获知数据包下一跳的分发路径的。对于BLE / Wi-Fi 这类无线局域网通讯协议，主从设备之间通讯并没有路由器或交换机，无线数据报文是如何传送转发的呢？

博文[链路层通信模式和空口协议设计](https://blog.csdn.net/m0_37621078/article/details/107724799) 介绍了BLE 广播通信与连接通信模式，广播通信是Advertiser 将数据包发送给附近所有的Scanner，而Scanner 可以接收到周围所有Advertiser 的数据包（包括过滤规则的需要符合过滤规则要求），所以抓取广播报文比较简单。

连接通信模式则是主从设备之间先建立连接，[连接的本质](https://blog.csdn.net/m0_37621078/article/details/106506532?spm=1001.2014.3001.5502#t6) 是通信双方之间记录并同步维护的状态构成的，比如对端设备的MAC 地址、绑定信息等，BLE 连接通信实际上就是只接收目标设备的数据报文，忽略掉非目标设备的数据报文，这是由协议层定义的。如果想抓取BLE 连接通信报文，需要修改协议层代码，让其在非连接模式下接收处于连接模式的通信报文，这种修改后的非标准协议代码通常配合专用的硬件使用（当然也可以使用标准硬件比如开发板配合非标准的sniffer 驱动代码使用，但驱动应与硬件匹配），比如BLE sniffer 设备。
![sniffer 设备连接示意图](https://img-blog.csdnimg.cn/20210406230246597.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
Nordic 为方便抓取并分析BLE 数据报文，提供了[BLE sniffer hex文件](https://www.nordicsemi.com/Software-and-tools/Development-Tools/nRF-Sniffer-for-Bluetooth-LE/Download#infotabs)，可以烧录到开发板或者dongle 设备中使用，nRF Sniffer for BLE 配合Wireshark 的使用说明详见文档：[nRF_Sniffer_BLE_UG_v3.2.pdf](https://infocenter.nordicsemi.com/pdf/nRF_Sniffer_BLE_UG_v3.2.pdf)， Nordic 提供的nRF Sniffer for BLE 驱动程序以及适用的开发板或dongle 如下表：
![nRF Sniffer firmware](https://img-blog.csdnimg.cn/20210406225623150.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
比如采用nRF52840 Dongle 作为sniffer 硬件设备，sniffer_nrf52840dongle_nrf52840_7cc811f.hex 作为sniffer 驱动程序，可以使用nRF connect for desktop --> Programmer 工具借助nRF52840 Dongle 内置的bootloader_usb 代码烧录sniffer 驱动程序）。比如采用nRF52 DK 作为sniffer 硬件设备（板载J-Link 并引出SWD 接口），sniffer_nrf52dk_nrf52832_7cc811f.hex 作为sniffer 驱动程序，可以使用nrfjprog 或J-Flash工具烧录sniffer 驱动程序。

Sniffer 设备烧录适用的sniffer 驱动程序后，PC 端安装wireshark，并在线安装nRF Sniffer capture tool，添加并选用Wireshark Profile_nRF_Sniffer_Bluetooth_LE，就可以使用sniffer BLE 设备配合wireshark 抓取BLE 数据包了，详细步骤可以参阅[nRF_Sniffer_BLE_UG_v3.2.pdf](https://infocenter.nordicsemi.com/pdf/nRF_Sniffer_BLE_UG_v3.2.pdf)，抓取到的BLE 数据报文格式如下：
![wireshark抓取BLE 数据报文图示](https://img-blog.csdnimg.cn/20210406230710589.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
借助wireshark 和nRF Sniffer 抓取的数据报文，可以对其进行过滤，只显示我们关注的数据报文（常见过滤条件如下表，多个过滤条件可通过逻辑运算符&& 或 || 组合在一起使用）。Wireshark 除了显示数据报文的原始数据，还可以解析BLE 报文每个协议层每个字段的含义，不用来回查询Core Spec 即可获知当前报文中关键字段的值是否合适。

| Display filter                        | Description                                                  |
| :------------------------------------ | :----------------------------------------------------------- |
| **btle.length != 0**                  | Filter that displays only packets where the length field of the Bluetooth Low Energy packet is not zero, meaning it hides empty data packets. |
| **btle.advertising_address**          | Filter that displays only packets that have an advertising address (advertising packets). |
| **btle**                              | Protocol filter that displays all Bluetooth Low Energy packets. |
| **btatt**<br>**btsmp**<br>**btl2cap** | Protocol filters for ATT, SMP, and L2CAP packets, respectively. |

如果连接双方配对或绑定了，也即BLE 交互数据报文加密了，在Wireshark --> Passkey / OOB Key 窗口输入6位配对码就可以解析加密的报文了（LESC 配对采用ECDH 密钥协商算法，sniffer 只靠6 位配对码无法计算出用于解密报文的共享密钥，还需要知道配对双方之一的私钥才能计算出配对双方加解密报文使用的共享密钥）。
![Enter the credentials for pairing by type of encryption](https://img-blog.csdnimg.cn/20210410124306723.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
Wireshark 可以显示抓取数据报文中每个字段的解析注释，也包含时间信息，但wireshark 是为分析TCP/IP 协议而生的，分析BLE 时序图、瞬时数据流量、信道频谱、网络拓扑等信息还是略显不足。如果想获取更详细直观的BLE 数据报文交互信息，可以使用Ellisys 来抓包分析BLE 数据报文，其抓取到的报文解析图示如下：
![Ellisys 抓包分析图示](https://img-blog.csdnimg.cn/20210406234755953.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
Ellisys 抓包需要借助专用的设备（蓝牙协议分析仪）比如Ellisys Bluetooth Explorer、Ellisys Bluetooth Tracker 等，这些专业设备成本大概二三十万，一般专业的蓝牙开发团队才会选择使用这些蓝牙分析仪。相比较而言，前面介绍的wireshark 配合nRF sniffer 的抓包分析方案成本或门槛低得多，一般简单的BLE profile/service 开发使用这种低成本的抓包分析方案也能满足需求，本文就使用这种方案介绍BLE 通信过程中数据报文的交互了。

# 二、BLE 通信报文是如何交互的？

从博文[协议栈架构设计](https://blog.csdn.net/m0_37621078/article/details/107411324)，我们知道BLE 协议栈类似TCP/IP 协议栈，也是分层设计的，从下到上依次是Physical Layer、Link Layer、L2CAP、Security Manager 或Attribute Protocol、GAP 或GATT 这几层，每层协议都有相应的header 和payload，BLE 数据包也是逐层协议字段封装嵌套的。
![softdevice stack architecture](https://img-blog.csdnimg.cn/20210409105851185.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Host 不同模块也不是同时工作的，GAP 主要负责广播通信与连接建立过程，Security Manager 主要负责通信双方之间的配对和绑定过程，GATT 主要负责服务发现、服务数据传输等连接通信过程，本文也分这几个过程简单介绍BLE 数据报文的封装与交互。

下文使用的软硬件环境如下：

 - **SDK project**：.\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_hrs (s132_nrf52_7.2.0_softdevice.hex)
 - **BLE peripheral**：nRF52 development kits (PCA10040)
 - **BLE central**：nRF connect for mobile version 4.24 (Android phone)
 - **BLE sniffer**：nRF52840 Dongle (sniffer_nrf52840dongle_nrf52840_7cc811f.hex) + Wireshark-win64-3.4.4
 - **Development Environment**：Setup_EmbeddedStudio_ARM_v540b_win_x64 + Windows 10_x64

编译工程ble_app_hrs 并将其烧录到nRF52 DK 中（softdevice 也需要烧录进去），PC 端打开wireshark（先插上BLE sniffer）并选择nRF Sniffer for Bluetooth LE COM* 开始捕获周围的BLE 数据包，wireshark --> nRF Sniffer toolbar --> Device 选择“Nordic_HRM” 设备只抓取该设备发送或接收的数据包。

手机端打开nRF connect 扫描并连接“Nordic_HRM” 设备，点击“Enable CCCDs” 使能notifications，为了看到更多LL Control Packet 可以点击“Request MTU”、“Request connection priority”、“Set preferred PHY” 等以更新MTU、connection parameters、PHY 等。为了抓取配对绑定过程的交互报文，可以点击"Bond"（工程ble_app_hrs 默认使用LE Secure Connections pairing with Just Works）手机端弹窗“配对请求” --> 点击“配对” ，Nordic_HRM 设备与手机完成配对与绑定过程。
![nRF connect enable CCCDs / request MTU / set PHY / Bond](https://img-blog.csdnimg.cn/20210410154342235.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
Wireshark 借助BLE Sniffer 抓取到了上述过程的交互报文，在双方完成配对和绑定过程后，Wireshark 抓取到的报文提示“Encrypted packet decrypted incorrectly (bad MIC)”，也即无法解密抓取到的加密报文。这说明BLE 4.2 之后使用的LE Secure Connections pairing 安全性大幅提升，密钥协商与加密报文可以防止被嗅探泄密，我们如何分析LESC 配对加密后的报文呢？这个问题下文再解答，我们先简单分析目前抓取到的报文。

## 2.1 GAP Discovery and Connection establishment procedures

BLE peripheral “Nordic_HRM” 上电启动后开始对外广播报文，我们先看抓取到的**ADV_IND 报文**，各字段注释及整个数据报文的封装格式如下：
![HRM ADV_IND PDU](https://img-blog.csdnimg.cn/20210410144626521.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
广播报文每个字段的含义就不展开介绍了，Advertiser（Nordic_HRM 设备）发送的ADV_IND 报文重点是PDU 字段，Packet Header 包含广播报文类型、信道选择算法、Tx / Rx 设备MAC 地址类型、Payload Length等信息，Payload 则包含Advertising Address、Advertising Data（以AD Structure 数组形式封装，每个AD Structure 项包含Length、Type、Data 三个字段）等信息。

对比底部“PACKET BYTES” 窗口内的原始数据，可以发现原始数据帧是以小端字节序、最低有效位比特序排列的。中间“PACKET DETAILS” 窗口内的字段，为了符合我们的阅读习惯，采用大端字节序排列的。

从该ADV_IND 报文Advertising Data 字段的Flags Structure 可知，Nordic_HRM 设备被配置为 LE General Discoverable Mode，可以被执行General Discovery procedure 的设备发现。从Service Class UUIDs Structure可知，Nordic_HRM 设备提供了Heart Rate Service、Battery Service、Device Information Service 这三种服务。

手机端nRF connect 可以通过ADV_IND 报文发现Nordic_HRM 设备了，nRF connect --> SCANNER 界面选择“Nordic_HRM” 并点击“CONNECT”，手机端向目标Nordic_HRM 设备发送CONNECT_IND 报文请求建立连接，**CONNECT_IND 报文**各字段注释及整个数据报文的封装格式如下：
![HRM CONNECT_IND PDU](https://img-blog.csdnimg.cn/20210410171342429.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
CONNECT_IND 报文Packet Payload 字段包含Initiator Address、Advertising Address、Link Layer Data 三部分，其中Link Layer Data 包含Access Address、CRC Init、请求连接参数（transmitWindowSize、transmitWindowOffset、connInterval、connSlaveLatency、connSupervisionTimeout）、Channel Map（每一位表示一个对应信道是否使用，共37 个数据信道，剩余3 位预留未用）、Hop Increment（参与信道选择算法的一个参数，值为 5 ~ 16 的一个随机数）、Master’s sleep clock accuracy 等信息。

Initiator（手机端nRF connect ）使用Primary Physical channel 发送CONNECT_IND 后直接进入Connection State，发起者并不知道对方是否接收到了CONNECT_IND 报文，双方建立连接后在发送CONNECT_IND 报文的LE 1M PHY 上通信（后续可以通过PHY Update procedure 更换到其它PHY）。如果Initiator 使用Secondary Physical channel 发送AUX_CONNECT_REQ 报文请求建立连接，还需要等待接收到对方回复的AUX_CONNECT_RSP 报文后才进入Connection State，双方建立连接后在发送AUX_CONNECT_REQ 报文的PHY 上通信（可以是LE 1M PHY、LE 2M PHY 或LE Coded PHY）。

## 2.2 Link Layer Control procedure

BLE Peripheral 与BLE Central 建立连接后，双方需要先交换一些信息（比如Feature、Version 等），更新一些参数（比如Connection Parameters、Channel Map、Data Length、PHY、Sleep Clock Accuracy、Power Control 等），如果对通信安全有需求，还需要进行密钥协商、密钥分发、绑定等过程，这都是为了连接双方更高效的通信（可参阅博文：[Link Layer Control Protocol](https://blog.csdn.net/m0_37621078/article/details/107724799?spm=1001.2014.3001.5501#t12)）。

BLE 双方建立连接后，随即开始**Feature Exchange procedure**，我们看看BLE Peripheral 与BLE Central 都分别支持哪些Feature：
![HRM Feature Exchange procedure PDU](https://img-blog.csdnimg.cn/20210410212302827.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
从LL_FEATURE_REQ / LL_FEATURE_RSP 报文的Feature Set 值可知，双方都支持LE Encryption、Extended Reject Indication、LE Data Packet Length Extension、LE 2M PHY、Channel Selection Algorithm #2 等Feature，Master 或Central 还支持Connection Parameters Request Procedure、LE Ping、Extended Scanner Filter Policies、LE Coded PHY、LE Extended Advertising、LE Periodic Advertising 等Feature。

受限于篇幅，我们只挑几个比较重要常见的Link Layer Control Packet 看一下。跟BLE 传输速率和平均功耗直接相关的Link Layer Control procedure 有Data Length Update procedure、Connection Parameters Update procedure、PHY Update procedure 等。我们先看**Data Length Update procedure**：
![HRM Data Length Update procedure PDU](https://img-blog.csdnimg.cn/20210410235744631.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Peripheral 与BLE Central 均支持BLE 5.x 版本（双方通过Version Exchange procedure 交换BLE 版本信息），通过LL_LENGTH_REQ 和LL_LENGTH_RSP 将链路层支持的数据报文payload length更新到 251 octets。接下来看**Connection Parameters Update procedure**：
![HRM Connection Parameters Update procedure PDU](https://img-blog.csdnimg.cn/20210411002804338.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Master / Central 可通过向BLE Slave /Peripheral 发送 LL_CONNECTION_UPDATE_IND 报文强制更新连接参数，也可以像上面那样BLE Slave /Peripheral 向BLE Master / Central 发起更新连接参数的请求，BLE Master / Central 接受BLE Slave /Peripheral 请求的连接参数。一般情况下，BLE Slave /Peripheral 权衡数据传输速率和功耗续航要求，都精心设计了连接参数的建议值，BLE Master / Central 通常也会接受这些建议值。再看**PHY Update procedure**：
![HRM PHY Update procedure PDU](https://img-blog.csdnimg.cn/20210411005827665.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Peripheral 与BLE Central 既然都支持BLE 5.x 版本，自然也都支持LE 2M PHY，BLE Master / Slave 任一方都可以发起更新PHY 的请求，上图是Master 发起的请求，双方通过PHY Update procedure 将PHY 更新到LE 2M PHY，可以提高BLE 链路层数据吞吐率。

## 2.3 GATT Service Discovery and Characteristic Read/Write procedure

BLE Peripheral 与BLE Central 建立连接，二者交换或更新一些必要的连接信息后，BLE Central 借助GATT 开始发现并访问BLE Peripheral 提供的服务。在GATT Service Discovery 之前，双方还需要先交换各自支持的MTU，**Exchange MTU (Maximum Transmission Unit) procedure** 如下：
![HRM Exchange MTU procedure PDU](https://img-blog.csdnimg.cn/20210411134837731.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
上图Exchange MTU Request / Response 报文交换双方支持的MTU 均为247 Octets，L2CAP Header 占用4 octets，对应到Link Layer Payload 就是251 octets。前面介绍的LLCP Data Length Update procedure 是将Link Layer Payload length 更新到251 octets，也即对上层ATT MTU 不需要分包就可以直接经Link Layer 发送出去，如果ATT MTU > LL Max Tx Data Length，则L2CAP 需要先对ATT PDU 拆分为不大于LL Max Tx Data Length 的数据包后，再递交给链路层发送。

BLE 连接双方交换MTU 后，BLE Central 开始发现BLE Peripheral 提供的Service、Characteristic、Characteristic Descriptor 等（该过程可参阅博文：[GATT feature and procedure](https://blog.csdn.net/m0_37621078/article/details/108391261?spm=1001.2014.3001.5501#t7)），**Primary / Include Service Discovery procedure** 如下（Attribute Parameters 可参阅博文：[Attribute protocol methods](https://blog.csdn.net/m0_37621078/article/details/108391261?spm=1001.2014.3001.5501#t10)）：
![HRM Primary Service Discovery procedure PDU](https://img-blog.csdnimg.cn/20210411142802664.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Central 发现NORDIC_HRM 设备提供了5个 Primary Service，分别是Generic Access Profile、Generic Attribute Profile、Heart Rate、Battery Service、Device Information，其中前两个是通用服务。

BLE Central Discovery Primary Service 后（该示例工程没有Include Service）开始Discovery Characteristic 和Characteristic Descriptor，下面只展示**Discovery Heart Rate Measurement Characteristic procedure** 如下：
![HRM Characteristic Discovery procedure PDU](https://img-blog.csdnimg.cn/20210411150259449.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Peripheral 提供的Primary Service: Heart Rate 提供了两个GATT Characteristic Declaration，分别是Heart Rate Measurement 和Body Sensor Location，每个Characteristic Declaration 都是一个Attribute（包含Attribute Handle、Type UUID、Attribute Value、Attribute Properties 四个部分）。其中Heart Rate Service: Heart Rate Measurement Characteristic还包含一个Characteristic Descriptor（可通过Characteristic Descriptor Discovery procedure 获知），即 Heart Rate Service : Heart Rate Measurement Characteristic: Client Characteristic Configuration Descriptor，该**Descriptor Discovery procedure 和Descriptor Value Write procedure** 如下（下图省略了有效信息较少的Find Information Request 和Write Response 报文）：
![HRM CCCD Discover and Write procedure PDU](https://img-blog.csdnimg.cn/2021041116053140.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE Client/Central 发现了Heart Rate Measurement Characteristic: Client Characteristic Configuration Descriptor 并向BLE Server/Peripheral 写入该CCCD Value 为Notification，BLE Server/Peripheral 就可以Notification 的形式主动向BLE Client/Central 发送Heart Rate Service: Heart Rate Measurement Characteristic Value 数据。

我们只看Heart Rate Service，其中Heart Rate Measurement Characteristic Value 以Notification 的形式发送给BLE Client（前面已Enable CCCDs / Notification ），Body Sensor Location Characteristic Value 则需要BLE Client 通过Read Request 报文读取相应的Characteristic Value。**Characteristic Value Notifications 和Characteristic Value Read procedure** 如下：

![在这里插入图片描述](https://img-blog.csdnimg.cn/20210411194638918.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE GATT Client 读取BLE GATT Server Body Sensor Location Characteristic Value 为Finger，也即通过手指测量心率。BLE GATT Server 以Notifications 形式发送给GATT Client 的Heart Rate Measurement Characteristic Value 包括HRM Flags、HRM Value、RR Intervals 等，HRM Flags 中的Sensor Support 和Sensor Contact 均为True 监测到的值才有效。上图HRM Value 值170 并不是UINT16 类型（从原始字节数据可知，该值为UINT8 类型），RR Intervals 是心电图上的QRS信号连续两个R波之间经过的时间（也可以理解为两次心跳节拍之间的时间间隔，比如RR Intervals = 400 ms，则HRM Value = 60 * 1000 / 400 = 150 bpm）。

## 2.4 LE secure connections Pairing procedure

 现在对物联网安全性都有较高的要求，BLE 设备要想保证通信安全，需要对数据包进行加密。在博文[TLS 加密原理](https://blog.csdn.net/m0_37621078/article/details/106028622) 中也介绍过，AES(Advanced Encryption Standard) 对称密钥加密可以保证通信的安全性，Diffie–Hellman 非对称密钥协商算法可以让通信双方安全的协商出共享对称密钥。

BLE 从Version 4.2 开始引入了新的密钥协商分发方案**LE secure connections**，该方案采用**ECDH**(Elliptic-Curve Diffie–Hellman) 非对称密钥协商算法，协商出用于对称加密的共享密钥，然后使用该共享密钥和**AES-CMAC** 对称加密算法对BLE 数据包进行加解密处理和完整性校验。

示例工程ble_app_hrs 默认使用LE secure connections，由于ECDH 密钥协商算法需要通信双方交换各自的公钥，我们不能保证收到的公钥就是我们期望连接的对端设备的公钥，这就可能带来MITM(Man-in-the-Middle Attack) 中间人攻击问题，该如何防止MITM 呢？

TLS 算法借助社会性基础设施PKI(Public-Key Infrastructure) 来认证公钥提供方的身份，将公钥申请者的Public-Key 和身份地址打包并由权威第三方的私钥签名为CA(Certificate Authority) 数字证书，通过交换CA 证书取代交换公钥，通信方可以很方便的验证CA 证书的合法性，从而解决MITM 问题。TLS 一般用于远端网络通信，才引入了PKI，BLE 属于近场局域网通信，没必要引入这么复杂的PKI 和CA，BLE 如何防止MITM 呢？

PKI 属于社会学范畴，合法性交由第三方权威机构保证，BLE 如何防止MITM 也可以交由人去保证。我们在连接需要加密通信的BLE 设备时，通常需要配对或绑定过程，BLE 设备配对时通常需要配对码，两个设备的配对码一样BLE 协议栈就认为通信双方都是合法可信的，设备配对码的比对一般需要人参与，这就靠人解决了BLE 防止MITM 的问题。

BLE 设备一般I/O 能力受限，该如何比较配对码呢？根据BLE 设备I/O 能力的不同，BLE 协议栈提供了四种不同的配对方式：**Just works**（默认配对码为0，不需要输入或显示任何配对码，因此不能防止MITM 攻击）、**Passkey**（人工输入目标设备显示的 6位配对码）、**Numeric comparison**（人工比较连接双方显示的配对码是否一致）、**Out-Of-Band**（通过带外传输配对码，比如NFC 传输，其是否能防止MITM 攻击取决于OOB 传输是否能防止MITM 攻击）等。Just works 是最简单不需要人参与判断的配对方式，因此不具备防止MITM 攻击的能力，其余三种配对方式都需要人参与判断，其是否能防止MITM 攻击取决于人为操作。

了解了LE secure connections 的原理，接下来看LE secure connections Pairing procedure：
![HRM BOND Encrypted packet decrypted incorrectly (bad MIC) PDU](https://img-blog.csdnimg.cn/20210411202048180.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
从上图可以看出，BLE Peripheral 和Central 完成配对绑定后，提示“Encrypted packet decrypted incorrectly (bad MIC)”，BLE Sniffer 无法解密配对后的加密报文，工程ble_app_hrs 默认使用的LE secure connections with Just Works，不需要输入任何配对码（也即配对码默认为0），为何无法解密呢？

LE secure connections Pairing 需要双方交换公钥，但连接双方的私钥是不公开也不交换的，Sniffer 并不知道通信双方任何一方的私钥，因此即便嗅探抓取了所有配对绑定过程的报文，也无法计算出双方协商出的共享密钥，自然无法解密配对后的数据包。如何解决该问题呢？

我们很容易想到两种解决方案：一种是将通信一方的私钥输入到Sniffer 抓包设备中（比如Ellisys 支持输入私钥来解密抓取的数据包）；另一种是使用通用的公私密钥对（也即提前预置到Sniffer 程序中的通用公私密钥对）。Nordic BLE Sniffer 如何解决该问题呢？我们查看文档得知如下信息：
![BLE DH Private/public key pair in Debug mode](https://img-blog.csdnimg.cn/20210411221721681.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE secure connections Pairing 有一个debug mode，在debug mode 使用统一的private / public key pair，这个key pair 提前预置到nRF_Sniffer 驱动程序中了，我们只需要配对双方中的任何一方处于debug mode 就可以通过Sniffer 解密配对加密后的数据报文了。我们修改工程ble_app_hrs 代码让其处于debug mode，实际上就修改一个宏变量如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_hrs\main.c

#define LESC_DEBUG_MODE                     1                                       /**< Set to 1 to use LESC debug keys, allows you to use a sniffer to inspect traffic. */
```

重新编译工程并烧录到nRF52 DK 中，使用Wireshark + Sniffer 抓取“NORDIC_HRM” 设备的数据包，使用手机端nRF connect 请求配对绑定操作，绑定成功后依然出现“Encrypted packet decrypted incorrectly (bad MIC)” 无法解密数据包的问题，这又是为何呢？

我们在工程中搜索关键词“LESC_DEBUG_MODE”，除了上述宏定义外，整个工程其它地方并没有使用到这个宏变量，这个宏变量是无意义的吗？我们到[Nordic DevZone](https://devzone.nordicsemi.com/) 网站搜索关键词“LESC_DEBUG_MODE”，总算找出点有用信息（[搜索结果](https://devzone.nordicsemi.com/f/nordic-q-a/37078/lesc_debug_mode-define-in-ble_app_multirole_lesc-nrf5-sdk-15-0-0?ReplySortBy=CreatedDate&ReplySortOrder=Descending)），大意是说Nordic 不希望客户在其最终产品代码中意外启用debug mode，所以从SDK 15.0 后删除了debug keys。

既然Nordic SDK 17 删除了debug keys，我们想使用debug mode 的话，需要手动在代码中添加debug keys（重点是debug private key）。在那个帖子中也提供了添加debug private key 的方法，代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\libraries\crypto\backend\oberon\oberon_backend_ecc.c

ret_code_t nrf_crypto_backend_oberon_ecc_secp256r1_rng(uint8_t data[32])
{
#if NRF_MODULE_ENABLED(NRF_CRYPTO_RNG)

#ifdef DEBUG

    static const uint8_t LESC_DEBUG_KEY[32] =
    {

      0x3f, 0x49, 0xf6, 0xd4, 0xa3, 0xc5, 0x5f, 0x38, 0x74, 0xc9, 0xb3, 0xe3, 0xd2, 0x10, 0x3f, 0x50,

      0x4a, 0xff, 0x60, 0x7b, 0xeb, 0x40, 0xb7, 0x99, 0x58, 0x99, 0xb8, 0xa6, 0xcd, 0x3c, 0x1a, 0xbd,
    };

    for (int i=0; i < sizeof(LESC_DEBUG_KEY); i++)
        data[i] = LESC_DEBUG_KEY[i];

    return NRF_SUCCESS;

#else

    static const uint8_t min_value[32] =
    {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
    };
    static const uint8_t max_value[32] =
    {
        0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84, 0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x50,
    };
    return nrf_crypto_rng_vector_generate_in_range(data, min_value, max_value, 32);

#endif

#else
    return NRF_ERROR_CRYPTO_FEATURE_UNAVAILABLE;
#endif
}
```

BLE 设备的公私密钥对是自己随机生成的，上述代码实际上是让BLE 工程处于Debug 模式时返回debug private pair 作为私钥，而不是自己随机生成的，这就相当于让BLE 设备处于debug mode 了。我们也可以将main 文件中定义的宏变量LESC_DEBUG_MODE 值改为DEBUG，提醒我们是否使用了LESC debug keys。

我们选择工程ble_app_hrs 的Debug 配置，重新编译并烧录到nRF52 DK 中，使用Wireshark + Sniffer 抓取“NORDIC_HRM” 设备的数据包，使用手机端nRF connect 请求配对绑定操作，这次可以正常解密配对绑定后加密的数据报文了。

[BLE secure connections Pairing procedure 可分为三个阶段](https://blog.csdn.net/m0_37621078/article/details/107850523?spm=1001.2014.3001.5501#t10)：Pairing Feature Exchange、Authenticating and Encrypting、Transport Specific Key Distribution，我们先看Pairing Feature Exchange procedure：
![HRM Pairing Feature Exchange procedure PDU](https://img-blog.csdnimg.cn/20210411235632878.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE 配对双方通过Pairing Feature Exchange procedure 交换各自支持的IO Capability、OOB data flag、Authentication requirements flags、Maximum Encryption Key Size、Initiator Key Distribution / Generation、Responder Key Distribution / Generation 等信息，为后续密钥协商和密钥分发做准备。BLE Slave / Peripheral 既无输入又无输出能力、使用LESC 配对、配对后执行绑定过程、不具备防止MITM 攻击能力、密钥协商完成后分发LTK 和IRK。

LE secure connections Pairing 第二阶段Authenticating and Encrypting procedure 包括Public key exchange、Authentication stage 1、Long Term Key calculation、Authentication stage 2 (DHKey checks) 这几个小阶段，报文交互过程如下：
![HRM Authenticating and Encrypting procedure PDU](https://img-blog.csdnimg.cn/20210412011806326.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

经过LESC 配对的第二阶段Authenticating and Encrypting procedure 后，配对双方生成LTK（用于生成AES 对称加密的共享密钥）。在进行LESC 第三阶段Transport Specific Key Distribution 前，需要先使用LTK 加密当前的通信链路，生成的密钥需要在加密链路上分发才能保证安全性。

[LE Encryption procedure](https://blog.csdn.net/m0_37621078/article/details/107724799?spm=1001.2014.3001.5501#t12) 属于Link Layer Control Protocol 的范畴，通过LL_ENC_REQ / LL_ENC_RSP 报文交换SKD(Session Key Diversifier) 和IV(Initialization Vector) 信息，然后通过LL_START_ENC_REQ / LL_START_ENC_RSP 报文完成三次握手后启动数据链路加密过程，后续发送接收的数据包都是在加密链路上传输的，该过程交互的数据报文如下：
![HRM LE Encryption procedure PDU](https://img-blog.csdnimg.cn/20210412012052311.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

LESC 配对第三阶段Transport Specific Key Distribution procedure 主要分发LTK 和IRK（从Pairing Feature Exchange procedure 获知），LTK 是双方协商计算出来的，SDK 和IV 也已经在LE Encryption procedure 中交换过了，只剩下IRK 的分发了，该过程交互报文如下：
![HRM Transport Specific Key Distribution procedure PDU](https://img-blog.csdnimg.cn/2021041201233012.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
到这里，LESC 配对过程的三个阶段就完成了，绑定过程实际上就是将配对过程的必要信息保存到Flash 中，以便下次连接时直接使用，不需要再执行一遍配对过程。

本工程源码下载地址：[https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/examples/ble_peripheral\ble_app_hrs](https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/examples/ble_peripheral%5Cble_app_hrs)。


# 更多文章：

 - [《如何实现BLE 最大数据吞吐率并满足设计功耗要求？》](https://blog.csdn.net/m0_37621078/article/details/115483595)
 - [《如何实现扫码连接BLE 设备的功能?》](https://blog.csdn.net/m0_37621078/article/details/107193411)
 - [《nRF_Sniffer_BLE_UG_v3.2.pdf》](https://infocenter.nordicsemi.com/pdf/nRF_Sniffer_BLE_UG_v3.2.pdf)
 - [《Nordic_nRF5_Project》](https://github.com/StreamAI/Nordic_nRF5_Project)
 - [《Nordic nRF5 SDK documentation》](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/index.html)
 - [《BLE 技术（三）--- Link Layer Packet format 》](https://blog.csdn.net/m0_37621078/article/details/107697019)
 - [《BLE 技术（四）--- Link Layer communication protocol 》](https://blog.csdn.net/m0_37621078/article/details/107724799)
 - [《BLE 技术（五）--- Generic Access Profile》](https://blog.csdn.net/m0_37621078/article/details/107850523)
 - [《BLE 技术（六）--- GATT Profile + ATT protocol》](https://blog.csdn.net/m0_37621078/article/details/108391261)
 - [《Bluetooth Core Specification_v5.2》](https://www.bluetooth.com/specifications/bluetooth-core-specification/)