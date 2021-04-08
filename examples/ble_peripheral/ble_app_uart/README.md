# 如何平衡BLE 传输速率与平均功耗？

@[toc]

> 我们开发的BLE 设备多数都有两点要求：一是低功耗，电池供电需要持续工作数周甚至数个月；二是将BLE peripheral产生的数据快速传送给central，传输数据功耗较高，提高传输速率缩短传输时间也有利于降低平均功耗。我们该如何设置广播参数与连接参数以达到我们要求的功耗呢？该如何设置连接参数与报文长度（PDU / MTU）以尽可能达到最大传输速率呢？

# 一、如何提高BLE 数据传输速率？
BLE 数据传输相关的服务中有一个比较基础的串口透传服务，本文以nRF5_SDK_17.0.2 中的ble_app_uart 工程为例，展示如何提高BLE 的数据传输速率。

在尝试提高BLE 数据传输速率前，需要先获得两个信息：

 1. 当前使用的BLE 协议栈支持的理论最大数据吞吐率是多少？
 2. 如何获知当前的BLE 数据传输速率是多少？

## 1.1 Nordic BLE 最大数据吞吐率是多少？
对于第一个问题，我们可以从Nordic 协议栈规格说明书中获知，比如使用s132 softdevice 可以参考文档：[S132 SoftDevice SoftDevice Specification v7.1](https://infocenter.nordicsemi.com/pdf/S132_SDS_v7.1.pdf)，查阅Bluetooth Low Energy data throughput 章节，数据传输速率使用下面的公式：

```c
#define OPCODE_LENGTH        1
#define HANDLE_LENGTH        2

Throughput_bps = num_packets * (ATT_MTU - OPCODE_LENGTH - HANDLE_LENGTH) * 8 / seconds
```

这里统计的传输数据指的是应用数据，ATT_MTU 减去Attribute protocol PDU Opcode 和Attribute Handle 字段长度，剩下的就是Attribute Value 字段（也即有效的应用数据）。每个字节占8 比特，下表中的传输速率单位是kbps（如果要换算成 KB/s 需要除以8），下表Connection interval 与Connection Event Length 相等：
![S132 softdevice data throughput](https://img-blog.csdnimg.cn/20210407143456429.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
从上表可知，跟传输速率相关的因素主要有**ATT MTU size、Connection interval、Connection Event Length、Communication Mode、LE PHY speed** 等。比如ATT MTU size 为23、Connection interval 与Connection Event Length 取7.5 ms、Communication Mode 为Send Notification、LE 1M PHY 的最大速率为24 KB/s；ATT MTU size 为247、Connection interval 与Connection Event Length 取50 ms、Communication Mode 为Send Notification、LE 2M PHY 的最大速率为165.94 KB/s。

## 1.2 如何获知BLE 当前数据吞吐率？
一般BLE peripheral 作为GATT Server 向BLE central 也即GATT Client 传输数据，想获得BLE 当前的数据吞吐率，一般有三种方式：

 1. BLE peripheral 端统计单位时间内发送出去的数据量；
 2. BLE central 端统计单位时间内接收到的数据量；
 3. BLE sniffer 抓取单位时间内传输的报文中有效数据量。

Nordic 手机端的应用并没有提供显示当前数据吞吐率的功能，我们开发GATT Server 应用再去修改BLE central 代码比较麻烦。BLE sniffer 抓包分析倒是比较方便，wireshark + nRF sniffer 抓包方案容易丢包也没有直接统计数据吞吐率指标，专业的蓝牙分析仪Ellisys Bluetooth Explorer 倒是可以直接统计数据吞吐率，蓝牙分析仪成本太高。因此，本文选择第一种方案，在BLE peripheral 代码中添加统计数据发送量的功能，并通过RTT Log 打印出来。

我们在.\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart 示例工程的基础上添加统计单位时间内数据发送量的代码，Nordic UART Service 我们在博文：[如何实现扫码连接BLE 设备的功能？](https://blog.csdn.net/m0_37621078/article/details/107193411) 中已经介绍过了，二者主要的代码逻辑差不多，主要有两点不同：

 - **ble_app_uart 工程**在GAP 阶段作为Advertiser，在函数advertising_init 中初始化广播包内容、广播间隔、广播超时时间等，然后在函数advertising_start 中开始广播；**ble_app_uart_c 工程**在GAP 阶段作为Scanner 和Initiator，在函数scan_init 中设置扫描过滤条件、注册scan_evt_handler 等，然后在函数scan_start 中开始扫描周围的广播设备；
 -  **ble_app_uart 工程**在GATT 阶段作为GATT Server，在函数services_init --> ble_nus_init 中添加NUS service（包括RX Characteristic、TX Characteristic）、注册nus_data_handler 等，其中NUS 为Primary Service 对外提供串口透传服务；**ble_app_uart_c 工程**在GATT 阶段作为GATT Client，在函数db_discovery_init 和nus_c_init 中发现对端设备提供了哪些services（特别是NUS 服务）、注册db_disc_handler 和ble_nus_c_evt_handler 等，发现NUS 服务后就可以访问该服务了。

本文就不展开介绍ble_app_uart 工程代码逻辑了，我们重点关心的是GATT Server 如何使用NUS 服务向GATT Client 发送数据。从函数uart_event_handle 代码可以看出，使用函数ble_nus_data_send 可以通过NUS 服务向对端设备发送数据，该函数的声明如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_services\ble_nus\ble_nus.h

/**@brief   Function for sending a data to the peer.
 *
 * @details This function sends the input string as an RX characteristic notification to the
 *          peer.
 *
 * @param[in]     p_nus       Pointer to the Nordic UART Service structure.
 * @param[in]     p_data      String to be sent.
 * @param[in,out] p_length    Pointer Length of the string. Amount of sent bytes.
 * @param[in]     conn_handle Connection Handle of the destination client.
 *
 * @retval NRF_SUCCESS If the string was sent successfully. Otherwise, an error code is returned.
 */
uint32_t ble_nus_data_send(ble_nus_t * p_nus,
                           uint8_t   * p_data,
                           uint16_t  * p_length,
                           uint16_t    conn_handle);
```

既然是统计单位时间内GATT Server 发送出去的数据量，自然需要一个定时器资源，我们选用低功耗的app_timer。为了提高数据发送速率，我们选择Send Notification 模式。为了少做无用功，我们在NUS Notification enable 的情况下再开始发送数据，当连接断开后便停止发送数据。新增用于统计BLE data throughput 的代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c

/**@brief Resources related to throughput testing.
 */
#define DATA_THROUGHPUT_INTERVAL            APP_TIMER_TICKS(5)                   /**< data throughput interval (ticks). */
APP_TIMER_DEF(m_timer_throughput_id);

uint32_t m_data_sent_length = 0;
uint8_t m_data_array[BLE_NUS_MAX_DATA_LEN] = {0};

/**@brief Data generation timer timeout handler function.
 */
static void data_throughput_timeout_handler(void * p_context)
{
    UNUSED_PARAMETER(p_context);
    
    static uint32_t timeout_count = 0;
    ret_code_t err_code;
    
    timeout_count++;

    do
    {
        uint16_t length = BLE_NUS_MAX_DATA_LEN;
        err_code = ble_nus_data_send(&m_nus, m_data_array, &length, m_conn_handle);
        if ((err_code != NRF_ERROR_INVALID_STATE) &&
            (err_code != NRF_ERROR_RESOURCES) &&
            (err_code != NRF_ERROR_NOT_FOUND))
        {
            APP_ERROR_CHECK(err_code);
        }

        if(err_code == NRF_SUCCESS)
        {
            m_data_sent_length += length;
            m_data_array[0]++;
            m_data_array[length-1]++;
        }
    } while (err_code == NRF_SUCCESS);

    // Timer interval 5 ms, when the timer reaches 1 second 
    if(timeout_count == 200)
    {
        // Send m_data_sent_length bytes of data within 1 second, which is equal to m_data_sent_length * 8 / 1024 kilobits of data
        NRF_LOG_INFO("****** BLE data throughput: %d kbps ******", m_data_sent_length >> 7);
        m_data_sent_length = 0;
        timeout_count = 0;
    }
}

/**@brief Function for initializing the timer module.
 */
static void timers_init(void)
{
    ......
    // Create a data generation timer for testing throughput.
    err_code = app_timer_create(&m_timer_throughput_id, 
                                APP_TIMER_MODE_REPEATED, 
                                data_throughput_timeout_handler);
    APP_ERROR_CHECK(err_code);
}

/**@brief Function for handling the data from the Nordic UART Service.
 */
static void nus_data_handler(ble_nus_evt_t * p_evt)
{

    if (p_evt->type == BLE_NUS_EVT_RX_DATA) {
        ......
    } else if(p_evt->type == BLE_NUS_EVT_COMM_STARTED) {
        // Start data throughput timers.
        ret_code_t err_code;
        err_code = app_timer_start(m_timer_throughput_id, 
                                   DATA_THROUGHPUT_INTERVAL,
                                   NULL);
        APP_ERROR_CHECK(err_code);
    }
}

/**@brief Function for handling BLE events.
 */
static void ble_evt_handler(ble_evt_t const * p_ble_evt, void * p_context)
{
    uint32_t err_code;

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_CONNECTED:
            ......
        case BLE_GAP_EVT_DISCONNECTED:
            ......
            // Stop data throughput timers.
            err_code = app_timer_stop(m_timer_throughput_id);
            APP_ERROR_CHECK(err_code);
            break;

        case BLE_GAP_EVT_PHY_UPDATE_REQUEST:
        ......
    }
}
```

上述代码主要包含两部分：

 1. app_timer 资源的创建、开始与结束，包括超时回调函数的注册。当NUS Notification enable 事件发生时开始定时器，当连接断开时停止定时器；
 2. 超时回调函数data_throughput_timeout_handler 的实现，主要有两个任务：一是调用函数ble_nus_data_send 发送数据（参照函数uart_event_handle 内调用函数ble_nus_data_send 并检查返回值的代码，仅当返回NRF_SUCCESS 时才计入已发送数据）；二是通过RTT Log 打印1 秒内发送出去的数据量。

值得一提的是，每个定时周期可以发送不止一个数据包，博文[链路层空口报文设计](https://blog.csdn.net/m0_37621078/article/details/107697019?spm=1001.2014.3001.5501#t2) 中提到LE 1M PHY 发送最大PDU 约需2.3 ms，上面的代码设置的定时周期为5 ms，因此每个定时周期可以发送多个数据包，我们将ble_nus_data_send 放到循环体内，当返回值为NRF_SUCCESS 时继续循环发送下一个数据包。

通过RTT Log 打印当前BLE 数据吞吐量的代码已经实现了，编译工程 --> 将代码烧录到nRF52 DK 内，PC 端打开J-Link RTT Viewer，手机端打开nRF Connect for mobile。点击Enable CCCDs 或者Tx Characteristic 右边的图标使能NUS Notification，nRF52 DK 开始通过BLE 向手机端发送数据，nRF Connect --> Show log 可以查看接收到的数据，J-Link RTT Viewer 开始打印当前的BLE 数据吞吐率：
![RTT Log 打印BLE 数据吞吐量](https://img-blog.csdnimg.cn/20210407221038481.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

## 1.3 如何提高BLE 数据传输速率？
上图展示的BLE 数据吞吐率只有41 kbps，远低于nordic softdevice 支持的最大数据吞吐率，这是怎么回事呢？

BLE 数据吞吐率的计算公式：

```c
Throughput_kbps = num_packets * (ATT_MTU - 3) * 8 / 1000				// num_packets 为单位时间也即 1 秒内发送的数据包个数
				= (num_packets_interval / CONN_INTERVAL) * (ATT_MTU - 3) * 8 / 1000			// num_packets_interval 为单个连接间隔内发送的数据包个数，CONN_INTERVAL 为连接间隔，单位是秒
```

### 1.3.1 LE 1M PHY 最大数据吞吐率
上述工程默认的ATT_MTU 值为247，CONN_INTERVAL 为20 ~ 75 ms，由Throughput_kbps 等于41 kbps 可反推出num_packets_interval 等于1（CONN_INTERVAL 取中间值47.5 ms）。一个连接间隔只发送出去一个数据包，这大概是BLE 数据吞吐率这么低的主要原因吧，该如何提高BLE Throughput_kbps 呢？
![BLE Connection event](https://img-blog.csdnimg.cn/20210407225136459.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
前面也谈到，影响BLE Throughput_kbps 的因素主要有ATT MTU size、Connection interval、Connection Event Length、Communication Mode、LE PHY speed 等，ATT MTU size 已经设置为BLE 支持的最大值247，Connection Event 值为7.5 ms，也即一个连接周期最多只有Connection Event 时间传输数据，这个值远小于Connection interval，我们需要让Connection Event 占满Connection interval。为便于跟nordic softdevice 规格说明书中的值对比，这里设置连接参数如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c
#define MIN_CONN_INTERVAL               MSEC_TO_UNITS(50, UNIT_1_25_MS)             /**< Minimum acceptable connection interval (20 ms), Connection interval uses 1.25 ms units. */
#define MAX_CONN_INTERVAL               MSEC_TO_UNITS(50, UNIT_1_25_MS)             /**< Maximum acceptable connection interval (75 ms), Connection interval uses 1.25 ms units. */

// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\pca10040\s132\config\sdk_config.h
#define NRF_SDH_BLE_GAP_EVENT_LENGTH 40				// The time set aside for this connection on every connection interval in 1.25 ms units.

#define NRF_SDH_BLE_GAP_DATA_LENGTH 251
#define NRF_SDH_BLE_GATT_MAX_MTU_SIZE 247
```

编译工程 --> 烧录到nRF52 DK，J-Link RTT Viewer 打印RTT Log 信息如下：
![RTT Log NRF_ERROR_NO_MEM](https://img-blog.csdnimg.cn/20210407231512812.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
在执行函数sd_ble_enable 时返回NRF_ERROR_NO_MEM，也即分配给softdevice 的RAM 空间不足，需要为softdevice 预留更多的空间（也即缩减application 可用RAM 空间）。我们按照RTT Log 调整RAM_Start 和RAM_Size 如下：
![调整RAM_START与RAM_SIZE](https://img-blog.csdnimg.cn/20210407232436101.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
重新编译工程并烧录代码，nRF Connect for mobile 使能notification 或CCCDs，J-Link RTT Viewer 打印的BLE 数据吞吐率如下：
![RTT Log BLE data throughput 2](https://img-blog.csdnimg.cn/20210407234307480.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
BLE 最大数据吞吐率已经达到697 kbps了，很接近nordic softdevice 规格说明书中的702.8 kbps（也即87.85 KB/s），多打印会儿是可以看到BLE data throughput 达到七百以上的，BLE 数据传输速率达到了softdevice 支持的最大值。

如果已知Throughput_kbps 值为702.8 kbps，ATT_MTU 值为247，CONN_INTERVAL 值为50 ms，可以通过公式反求出单个连接间隔内发送出去的数据包个数为18，也即每个数据包以send notification 模式发送出去所需的平均时间为2.78 ms（包括radio 启动和切换时间、协议栈调度时间等）。

### 1.3.2 LE 2M PHY 最大数据吞吐率
从nordic softdevice 规格说明书可知，还可以使用BLE 5.0 新增的LE 2M PHY 特性进一步提高数据吞吐率。链路层使用LE 2M PHY，可以在更短的时间发送完等长度的数据包，也即在一个连接间隔可以发送更多的数据包，实现更大的传输速率。

当Connection interval 与Connection event 均为50 ms，ATT_MTU size 为247，采用Send Notification 通信模式和LE 2M PHY 物理链路，可以达到的Throughput_kbps 值为1327.5 kbps，通过公式可反求出单个连接间隔内发送出去的数据包个数为34，也即每个数据包以send notification 模式发送出去所需的平均时间为1.47 ms（由于radio 启动与切换时间、协议栈调度时间基本固定，因此发送单个数据包使用LE 2M PHY 比LE 1M PHY 所需时间的一半略多）。如何启用LE 2M PHY 呢？

前面通过修改宏变量值就可以更新Data Length 和Connection Parameters，这些更新过程在链路层有相应的控制报文交互（参阅博文：[Link Layer Control Protocol](https://blog.csdn.net/m0_37621078/article/details/107724799?spm=1001.2014.3001.5502#t12)），对于PHY Update 也有对应的链路层控制报文交互。
上述工程ble_app_uart 代码中跟PHY Update 相关的主要代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c
/**@brief Function for handling BLE events.
 */
static void ble_evt_handler(ble_evt_t const * p_ble_evt, void * p_context)
{
    uint32_t err_code;

    switch (p_ble_evt->header.evt_id)
    {
        ......
        case BLE_GAP_EVT_PHY_UPDATE_REQUEST:
        {
            NRF_LOG_DEBUG("PHY update request.");
            ble_gap_phys_t const phys =
            {
                .rx_phys = BLE_GAP_PHY_AUTO,
                .tx_phys = BLE_GAP_PHY_AUTO,
            };
            err_code = sd_ble_gap_phy_update(p_ble_evt->evt.gap_evt.conn_handle, &phys);
            APP_ERROR_CHECK(err_code);
        } break;
        ......
    }
}

// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gap.h
/**@defgroup BLE_GAP_PHYS GAP PHYs
 * @{ */
#define BLE_GAP_PHY_AUTO                         0x00    /**< Automatic PHY selection. Refer @ref sd_ble_gap_phy_update for more information.*/
#define BLE_GAP_PHY_1MBPS                        0x01    /**< 1 Mbps PHY. */
#define BLE_GAP_PHY_2MBPS                        0x02    /**< 2 Mbps PHY. */
#define BLE_GAP_PHY_CODED                        0x04    /**< Coded PHY. */
#define BLE_GAP_PHY_NOT_SET                      0xFF    /**< PHY is not configured. */

/**@brief Supported PHYs in connections, for scanning, and for advertising. */
#define BLE_GAP_PHYS_SUPPORTED  (BLE_GAP_PHY_1MBPS | BLE_GAP_PHY_2MBPS) /**< All PHYs except @ref BLE_GAP_PHY_CODED are supported. */
```

上面的代码是处理BLE_GAP_EVT_PHY_UPDATE_REQUEST 事件的，从BLE_GAP_PHYS_SUPPORTED 可以看出nRF52 DK 是支持BLE_GAP_PHY_2MBPS 的，变量phys 的值如果设置为BLE_GAP_PHY_1MBPS 或BLE_GAP_PHY_2MBPS 则强制选择相应的PHY，上述代码phys 设置为BLE_GAP_PHY_AUTO 则会自动选择当前最合适的PHY。如果在BLE central 端请求使用LE 2M PHY，BLE peripheral 端也会更新到LE 2M PHY（前提是BLE central 端与peripheral 端均支持LE 2M PHY，且peripheral 端未强制指定PHY）。

手机端是否支持LE 2M PHY，可以从nRF connect for mobile --> Device information 界面查看“High speed(PHY 2M) supported” 项为“YES” 表示支持LE 2M PHY。nRF connect for mobile 连接到nRF52 DK 广播名NORDIC_UART 后，点击“Enable CCCDs”使能NUS Notification，点击"Set preferred PHY" Tx/Rx PHY 均选择“LE 2M(Double speed)”。PC 端J-Link RTT Viewer 打印的BLE 数据吞吐率如下：
![LE 2M PHY 数据吞吐率](https://img-blog.csdnimg.cn/20210408001716796.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
我们看到了很奇怪的现象，理论上切换到LE 2M PHY，BLE 数据吞吐率应该提高近一倍的，实际情况却是大幅下降，这是怎么回事呢？

我们也是在每个定时周期循环发送数据包，直到函数ble_nus_data_send 的返回值不为NRF_SUCCESS 或者函数data_throughput_timeout_handler 被更高优先级的中断抢占（协议栈softdevice 事件的优先级高于application 中断的优先级）。同样的代码LE 1M PHY 可以接近最大数据吞吐率，切换到LE 2M PHY 数据吞吐率反而下降了，我们可以合理猜测循环发送数据包的过程出问题了，也即函数ble_nus_data_send 的返回值不是NRF_SUCCESS 而过早的退出了循环。该如何验证并解决该问题呢？

这里选用的[Send Notification 通信模式](https://blog.csdn.net/m0_37621078/article/details/108391261?spm=1001.2014.3001.5502#t10)，server 可以连续向Client 发送多个数据包而不需要等待response 或Confirmation 报文（Client 可能来不及处理数据包而直接丢弃），因此可以达到较高的数据吞吐率：
![BLE notification](https://img-blog.csdnimg.cn/20210408142105989.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
调用函数ble_nus_data_send，实际上是将应用层待发送数据指针传给softdevice 协议栈，放入到radio FIFO 中，当radio 将数据包成功发送出去后，softdevice 协议栈会返回BLE_GATTS_EVT_HVN_TX_COMPLETE 事件通知应用层数据包已成功发送出去。NUS 服务则会返回BLE_NUS_EVT_TX_RDY 事件通知应用层数据包已通过NUS 服务成功发送出去。

前面的问题既然猜测是由函数ble_nus_data_send 返回值非NRF_SUCCESS 而过早退出循环导致每个定时周期发送的数据包太少引起的，我们可以在每次触发BLE_NUS_EVT_TX_RDY 事件时再次循环调用函数ble_nus_data_send 发送下一个数据包。每成功发送一个数据包触发一次BLE_NUS_EVT_TX_RDY 事件，调用一次函数ble_nus_data_send，理论上应该能解决上述问题，我们添加如下代码：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c

/**@brief Function for handling the data from the Nordic UART Service.
 */
static void nus_data_handler(ble_nus_evt_t * p_evt)
{

    if (p_evt->type == BLE_NUS_EVT_RX_DATA) {
        ......
    } else if(p_evt->type == BLE_NUS_EVT_COMM_STARTED) {
        // Start data throughput timers.
        ......
    } else if (p_evt->type == BLE_NUS_EVT_TX_RDY) {
        ret_code_t err_code;
        
        do {
        	uint16_t length = BLE_NUS_MAX_DATA_LEN;
            err_code = ble_nus_data_send(&m_nus, m_data_array, &length, m_conn_handle);
            if ((err_code != NRF_ERROR_INVALID_STATE) &&
                (err_code != NRF_ERROR_RESOURCES) &&
                (err_code != NRF_ERROR_NOT_FOUND))
            {
                APP_ERROR_CHECK(err_code);
            }
        
            if(err_code == NRF_SUCCESS)
            {
                m_data_sent_length += length;
                m_data_array[0]++;
                m_data_array[length-1]++;
            }
        } while (err_code == NRF_SUCCESS);
    }
}
```

重新编译工程并烧录代码，nRF Connect for mobile 点击“Enable CCCDs”使能NUS Notification，点击"Set preferred PHY" Tx/Rx PHY 均选择“LE 2M(Double speed)”，J-Link RTT Viewer 打印的BLE 数据吞吐率如下：
![LE 2M PHY 最大吞吐率](https://img-blog.csdnimg.cn/20210408192445184.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
切换到LE 2M PHY 后，BLE 数据吞吐率果然大幅提升，上图显示吞吐率可以达到1220 kbps (也即152.5 KB/s)，已经比较接近nordic softdevice 支持的最大吞吐率1327.5 kbps 了，多打印会儿是可以看到BLE data throughput 达到一千三以上的，BLE 数据传输速率达到了softdevice 支持的最大值。

## 1.4  如何同步数据的生产与发送？
前面的代码直接对数组首尾字节自增后发送，实际应用场景中都是将断开连接期间暂时保存在本设备的数据或者sensor 实时产生的数据，在BLE 建立连接后分包发送给BLE Central 设备。如何保证数据包的有序发送呢？

我们很容易想到，可以借助FIFO 缓冲队列实现数据包的有序发送，这里使用[nordic 提供的queue 库](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/lib_queue.html)，生产出来的待发送数据有序入队，要发送的数据从队列中取用即可。

我们将上述持续发送BLE 数据包的代码修改为使用queue 的形式，首先需要将目录 .\nRF5_SDK_17.0.2_d674dde\components\libraries\queue 下的源文件和头文件路径添加进工程中，再在main.c 文件中包含"nrf_queue.h" 头文件，在main.c 中添加或修改如下代码：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c
......
#include "nrf_queue.h"
......
#define QUEUE_ELEMENT_NUMBERS               32
#define PKGS_PER_TIMER_PERIOD               8

uint8_t m_data_array[QUEUE_ELEMENT_NUMBERS][BLE_NUS_MAX_DATA_LEN] = {0};
typedef struct
{
    uint8_t * p_data;
    uint16_t length;
} m_element_t;

NRF_QUEUE_DEF(m_element_t, m_buf_queue, QUEUE_ELEMENT_NUMBERS, NRF_QUEUE_MODE_NO_OVERFLOW);
......
/**@brief Use queue to send ble data.
 */
void ble_data_send_with_queue(void)
{
    ret_code_t err_code;
    m_element_t data_item;
    uint16_t length = BLE_NUS_MAX_DATA_LEN;

    while(!nrf_queue_is_empty(&m_buf_queue))
    {
        err_code = nrf_queue_pop(&m_buf_queue, &data_item);
        APP_ERROR_CHECK(err_code);

        length = MIN(length, data_item.length);
        err_code = ble_nus_data_send(&m_nus, data_item.p_data, &length, m_conn_handle);
        if ((err_code != NRF_ERROR_INVALID_STATE) &&
            (err_code != NRF_ERROR_RESOURCES) &&
            (err_code != NRF_ERROR_NOT_FOUND))
        {
            APP_ERROR_CHECK(err_code);
        }
        if(err_code == NRF_SUCCESS)
            m_data_sent_length += length;
        else
            break;
    }
}

/**@brief Data generation timer timeout handler function.
 */
static void data_throughput_timeout_handler(void * p_context)
{
    UNUSED_PARAMETER(p_context);
    
    static uint32_t timeout_count = 0;
    ret_code_t err_code;

    static uint8_t value = 0;
    m_element_t data_item;
    uint16_t length = BLE_NUS_MAX_DATA_LEN;
    uint8_t pkgs = PKGS_PER_TIMER_PERIOD;
    
    timeout_count++;

    while (!nrf_queue_is_full(&m_buf_queue) && pkgs--)
    {
        m_data_array[value % QUEUE_ELEMENT_NUMBERS][0] = value;
        m_data_array[value % QUEUE_ELEMENT_NUMBERS][length-1] = value;

        data_item.p_data = &m_data_array[value % QUEUE_ELEMENT_NUMBERS][0];
        data_item.length = length;

        err_code = nrf_queue_push(&m_buf_queue, &data_item);
        APP_ERROR_CHECK(err_code);

        value++;
    }

    ble_data_send_with_queue();

    // Timer interval 5 ms, when the timer reaches 1 second 
    if(timeout_count == 200)
    {
        // Send m_data_sent_length bytes of data within 1 second, which is equal to m_data_sent_length * 8 / 1024 kilobits of data
        NRF_LOG_INFO("****** BLE data throughput: %d kbps ******", m_data_sent_length >> 7);
        m_data_sent_length = 0;
        timeout_count = 0;
        value = 0;
    }
}
......
/**@brief Function for handling the data from the Nordic UART Service.
 */
static void nus_data_handler(ble_nus_evt_t * p_evt)
{

    if (p_evt->type == BLE_NUS_EVT_RX_DATA) {
        ......
    } else if(p_evt->type == BLE_NUS_EVT_COMM_STARTED) {
        ......
    } else if(p_evt->type == BLE_NUS_EVT_TX_RDY) {
        ble_data_send_with_queue();
    }
}
```

使用queue 同步数据的产生与发送，队列未满时将生产的数据入队，队列非空时从队列中取出下一个元素通过调用函数ble_nus_data_send 将其发送出去。

编译工程报错，提示nrf_queue 函数未定义，我们需要在sdk_config.h 文件中启用NRF_QUEUE 模块相关的宏变量如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\pca10040\s132\config\sdk_config.h

#define NRF_QUEUE_ENABLED 1
```

重新编译工程并烧录代码，nRF Connect for mobile 点击“Enable CCCDs”使能NUS Notification，点击"Set preferred PHY" Tx/Rx PHY 均选择“LE 2M(Double speed)”，J-Link RTT Viewer 打印的BLE 数据吞吐率如下：
![use queue measure ble data throughput](https://img-blog.csdnimg.cn/20210408214844176.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
使用queue 同步数据产生与发送，PHY 使用LE 1M 时最大数据吞吐率为726 kbps，PHY 切换到LE 2M 时最大数据吞吐率为1334 kbps，均略高于nordic softdevice 支持的最大值，达到了我们预期的效果。

# 二、如何设置广播连接参数以满足低功耗需求？
我们开发的BLE peripheral 多数都有低功耗要求，由电池供电，如何满足电池续航需求呢？

Nordic 提供了nRF 芯片理论功耗计算网页[Online Power Profiler for BLE](https://devzone.nordicsemi.com/nordic/power/w/opp/2/online-power-profiler-for-ble)，我们可以在该页面修改参数，看理论功耗是否满足我们的设计要求。如果已经试产出产品了，也可以借助[Power Profiler Kit](https://www.nordicsemi.com/Software-and-tools/Development-Tools/Power-Profiler-Kit)  或[Power Profiler Kit II](https://www.nordicsemi.com/Software-and-tools/Development-Tools/Power-Profiler-Kit-2) 测量产品的真实功耗。

假设我们使用CR2032 纽扣电池（额定容量为220 mAh，额定电压3.0 V）供电，使用寿命一年，每天平均连接两个小时，其余时间处于idle 空闲状态，我们该如何设置广播参数与连接参数，以满足我们的设计续航要求呢？

假设我们选用nRF52832 芯片，Idle current 为2 uA，全年待机共消耗电量 = 365 * 24 * 2 uAh = 17.52 mAh。在产品寿命期间，BLE 连接通信时间约730 小时，可供BLE 连接消耗的电量约200 mAh，BLE 连接的平均功耗为274 uA。电池并不仅仅为BLE 通信供电，还为必要的传感器与外设工作供电，考虑到传感器与外设工作的时间比BLE 连接通信的时间更长，我们假设仅电池电量的1/3 供BLE 广播连接通信使用，其余2/3 为传感器和芯片外设工作供电，因此BLE 广播连接通信的平均功耗应控制在90 uA 左右。我们在Online Power Profiler for BLE 页面配置如下参数：
![BLE Advertising interval](https://img-blog.csdnimg.cn/20210408215422547.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
芯片选择nRF52832、CR2032 的额定电压为3.0 V、穿戴设备Radio Tx Power 选择 0 dBm 可以满足传输距离需求（可根据BLE 在空气中的路径损耗公式，结合通讯距离要求选择合适的Tx Power）。

DC/DC regulator 是一种效率很高的稳压器，原理是DC->AC->DC，既可以升压也可以降压。与之相比，还有一种低成本的LDO (Low Dropout regulator) 稳压器，效率比DC/DC 低些，只能降压使用且对输入输出电压差有限制。如果想达到更低的功耗，可以选择DC/DC，如果想进一步降低成本，可以选择LDO。这里我们选择更高效率的DC/DC regulator。

BLE 芯片通常需要两个时钟信号，比如nRF52 DK 上高频晶振频率为32 MHz、低频晶振频率为32.768 KHz，高频晶振驱动MCU 和高速外设工作，低频晶振可以大幅降低芯片的待机功耗（idle 或sleep 状态耗电的高频时钟关闭，仅保留低频时钟方便计时和唤醒）。高频时钟信号都需要外部晶振提供，低频时钟信号既可以外部晶振提供也可以使用MCU 内部的RC 振荡器获得。如果使用MCU 内部的RC 振荡器作为低频时钟则需要定期对其进行校准，需要大概 1.0 uA 的校准电流，且时钟精度略低些（较低的时钟精度也会增加BLE 通讯功耗）。

配置低频时钟信号的代码如下（工程ble_app_uart 默认选择的外部晶振作为低频时钟信号，若想选择MCU 内部振荡器作为低频时钟，修改sdk_config.h 中如下的四个宏变量值即可，本文选择默认的外部晶振）：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\common\nrf_sdh.c

/**@brief Function for requesting to enable the SoftDevice, is called in the function ble_stack_init.
 */
ret_code_t nrf_sdh_enable_request(void)
{
    ......
    nrf_clock_lf_cfg_t const clock_lf_cfg =
    {
        .source       = NRF_SDH_CLOCK_LF_SRC,
        .rc_ctiv      = NRF_SDH_CLOCK_LF_RC_CTIV,
        .rc_temp_ctiv = NRF_SDH_CLOCK_LF_RC_TEMP_CTIV,
        .accuracy     = NRF_SDH_CLOCK_LF_ACCURACY
    };
    ......
}

// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\pca10040\s132\config\sdk_config.h
......
// <h> Clock - SoftDevice clock configuration
//==========================================================
// <o> NRF_SDH_CLOCK_LF_SRC  - SoftDevice clock source.
 
// <0=> NRF_CLOCK_LF_SRC_RC 
// <1=> NRF_CLOCK_LF_SRC_XTAL 
// <2=> NRF_CLOCK_LF_SRC_SYNTH 

#ifndef NRF_SDH_CLOCK_LF_SRC
#define NRF_SDH_CLOCK_LF_SRC 1
#endif

// <o> NRF_SDH_CLOCK_LF_RC_CTIV - SoftDevice calibration timer interval. 
#ifndef NRF_SDH_CLOCK_LF_RC_CTIV
#define NRF_SDH_CLOCK_LF_RC_CTIV 0
#endif

// <o> NRF_SDH_CLOCK_LF_RC_TEMP_CTIV - SoftDevice calibration timer interval under constant temperature. 
// <i> How often (in number of calibration intervals) the RC oscillator shall be calibrated
// <i>  if the temperature has not changed.

#ifndef NRF_SDH_CLOCK_LF_RC_TEMP_CTIV
#define NRF_SDH_CLOCK_LF_RC_TEMP_CTIV 0
#endif

// <o> NRF_SDH_CLOCK_LF_ACCURACY  - External clock accuracy used in the LL to compute timing.
 
// <0=> NRF_CLOCK_LF_ACCURACY_250_PPM 
// <1=> NRF_CLOCK_LF_ACCURACY_500_PPM 
// <2=> NRF_CLOCK_LF_ACCURACY_150_PPM 
// <3=> NRF_CLOCK_LF_ACCURACY_100_PPM 
// <4=> NRF_CLOCK_LF_ACCURACY_75_PPM 
// <5=> NRF_CLOCK_LF_ACCURACY_50_PPM 
// <6=> NRF_CLOCK_LF_ACCURACY_30_PPM 
// <7=> NRF_CLOCK_LF_ACCURACY_20_PPM 
// <8=> NRF_CLOCK_LF_ACCURACY_10_PPM 
// <9=> NRF_CLOCK_LF_ACCURACY_5_PPM 
// <10=> NRF_CLOCK_LF_ACCURACY_2_PPM 
// <11=> NRF_CLOCK_LF_ACCURACY_1_PPM 

#ifndef NRF_SDH_CLOCK_LF_ACCURACY
#define NRF_SDH_CLOCK_LF_ACCURACY 7
#endif
```

BLE 广播通信阶段作为Advertising(connectable) role，假设TX payload 为31 bytes，当设置Advertising interval 为160 ms 时，Total average current 为87 uA，可满足我们的功耗需求，我们可以设置如下的宏变量（将Advertising interval 设置为160 ms）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c
......
#define APP_ADV_INTERVAL                256                                          /**< The advertising interval (in units of 0.625 ms. This value corresponds to 160 ms). */
#define APP_ADV_DURATION                18000                                       /**< The advertising duration (180 seconds) in units of 10 milliseconds. */
......
```

BLE 连接通信阶段作为Connection(peripheral) role，启用Data Packet Length Extension 和Connection Event Length Extension，假设TX payload per event 和RX payload per event 均为251 bytes，选择LE 1M PHY，我们在Online Power Profiler for BLE 页面配置如下参数：
![BLE connection interval and slave latency](https://img-blog.csdnimg.cn/20210408231244610.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
我们配置较小的Connection interval 可以在BLE peripheral 有数据传输需求时及时通知BLE central，配置较大的Slave latency 可以让BLE peripheral 在没有数据传输需求时跳过一定的连接事件以降低功耗。我们配置Connection interval 为25 ms、Slave latency 为 14 时，Total average current 为89 uA，可满足我们的功耗需求，我们可以设置如下的宏变量：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart\main.c
......
#define MIN_CONN_INTERVAL               MSEC_TO_UNITS(20, UNIT_1_25_MS)             /**< Minimum acceptable connection interval (20 ms), Connection interval uses 1.25 ms units. */
#define MAX_CONN_INTERVAL               MSEC_TO_UNITS(30, UNIT_1_25_MS)             /**< Maximum acceptable connection interval (30 ms), Connection interval uses 1.25 ms units. */
#define SLAVE_LATENCY                   14                                           /**< Slave latency. */
#define CONN_SUP_TIMEOUT                MSEC_TO_UNITS(4000, UNIT_10_MS)             /**< Connection supervisory timeout (4 seconds), Supervision Timeout uses 10 ms units. */
......
```

本工程源码下载地址：[https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/examples/ble_peripheral\ble_app_uart](https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/examples/ble_peripheral/ble_app_uart)。


# 更多文章：

 - [《如何实现扫码连接BLE 设备的功能?》](https://blog.csdn.net/m0_37621078/article/details/107193411)
 - [《Nordic_nRF5_Project》](https://github.com/StreamAI/Nordic_nRF5_Project)
 - [《Nordic nRF5 SDK documentation》](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/index.html)
 - [《BLE 技术（三）--- Link Layer Packet format 》](https://blog.csdn.net/m0_37621078/article/details/107697019)
 - [《BLE 技术（四）--- Link Layer communication protocol 》](https://blog.csdn.net/m0_37621078/article/details/107724799)
 - [《BLE 技术（五）--- Generic Access Profile》](https://blog.csdn.net/m0_37621078/article/details/107850523)
 - [《BLE 技术（六）--- GATT Profile + ATT protocol》](https://blog.csdn.net/m0_37621078/article/details/108391261)
 - [《Bluetooth Core Specification_v5.2》](https://www.bluetooth.com/specifications/bluetooth-core-specification/)