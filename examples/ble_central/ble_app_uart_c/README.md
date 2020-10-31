# Nordic_nRF5_Project
Connect the BLE target device by scanning the address code

# 前言
现在大部分蓝牙设备都不具备输入输出功能，主要靠蓝牙主机扫描发现周围的蓝牙从机，蓝牙从机需要处于广播模式才能被主机发现。蓝牙主机会将扫描发现的从机设备展示在一个列表中，你可以根据设备名称、类型和图标等信息，选择要连接哪一个从机设备。

如果周围有多个设备名称、类型和图标等信息都相同的从机设备，该怎么区分彼此呢？这种情况在物联网设备普及的当下也是经常遇到的。如果多个从机设备与蓝牙主机的距离有明显差异，可以通过扫描发现的设备列表先后排序区分彼此。蓝牙主机发现的设备列表是按照相对距离排序的，根据接收到广播报文的信号强度和报文中包含的发射功率等信息，蓝牙主机可以计算出每个蓝牙从机到主机的路径损耗，进而计算出每个蓝牙从机到主机的相对距离，距离蓝牙主机越近的从机设备，在扫描设备列表中的排序越靠前。

如果周围多个设备名称、类型和图标等信息都相同的从机设备到蓝牙主机的距离也相差无几，按照扫描设备列表排序来区分彼此可能就不准确了，这时候又该如何区分彼此呢？我们知道蓝牙设备的MAC 地址可以作为其唯一身份标识，每个蓝牙设备的MAC 地址都是不同的，我们可以通过蓝牙设备的MAC 地址来区分彼此。

目前市场上已经有很多蓝牙设备在其说明书中附带了该设备的MAC 二维码，我们只需要打开手机摄像头扫描该MAC 码即可连接该蓝牙设备，即便周围有很多同类设备，彼此的MAC 码也是不同的，因此可以将MAC 码作为区分彼此的依据，而且一扫即连（扫描MAC 码）、一碰即连（NFC 感应）等方式对使用者也更友好。

上述情况最常出现在工厂批量测试中，工厂在进行蓝牙设备测试时，首先需要连接到蓝牙设备才能进行后续的通信，旁边有很多同类型设备，这时就需要通过MAC 地址来区分彼此了。工厂生产的蓝牙设备大多是作为从机对外提供服务的，可以把PC 作为蓝牙主机，在PC 上连接一个摄像头或扫码枪来获取MAC 码信息，在PC 上开发一个通过MAC 地址自动连接蓝牙从机的程序，就可以实现蓝牙从设备与PC 之间一扫即连的进行通讯了。

本文以nRF52 BLE 芯片为例，使用nRF52 开发板作为蓝牙主机，来完成连接nRF52 从设备并进行通讯的任务。NRF52 开发板与PC 之间通过UART 协议通讯，PC 将获取到的从机MAC 地址通过UART 传给开发板，开发板根据获取到的MAC 地址连接指定的从机设备，建立连接后的通信数据也通过UART 在开发板与PC 之间传输。

![BLE Nordic UART Service](https://img-blog.csdnimg.cn/20201026110203434.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

# 一、nRF5 SDK 开发环境搭建
## 1.1 nRF5 SDK和SoftDevice 版本选择
Nodic 半导体为nRF52 BLE 芯片提供了nRF5 SDK 开发工具，SDK 内包含一些蓝牙应用示例，我们可以在此基础上开发我们需要的功能，比如我们可以在蓝牙透传示例代码基础上开发一扫即连的功能。

NRF52 芯片的BLE 驱动程序被封装为softdevice.hex 文件提供给用户了，开发者根据需要直接调用相应的API 就可以了，读者可以参考博文：[Nordic nRF5 SDK和softdevice介绍](https://www.cnblogs.com/iini/p/9095551.html)了解nRF5 开发环境搭建。

本文选用nRF52832 芯片作为从机设备的蓝牙模块，选用nRF52 DK board作为蓝牙主机，选择最新的nRF5_SDK_17.0.2 版本来开发应用。一扫即连功能主要是在蓝牙主机上实现的，选用的蓝牙协议栈softdevice 应支持ble_central (master) 角色，本文选用S132 类型最新版本s132_nrf52_7.2.0_softdevice，这也是nRF5_SDK_17.0.2 为nRF52 DK board PCA10040 默认提供的蓝牙协议栈版本。

![nRF5 softdevice 架构](https://img-blog.csdnimg.cn/20201022162831692.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

## 1.2 IDE 和J-Link 版本选择
Nordic 支持的IDE 开发工具主要有四种：Segger Embedded Studio、Keil MDK-ARM、IAR for ARM、ARM GCC 等，用户可以根据自己的使用习惯选择IDE 工具。考虑到Nordic 对Segger Embedded Studio 的支持更友好，且Nordic 已经购买了Segger Embedded Studio for Nordic 的License，用户不需要再为License 付费，Segger Embedded Studio 更有跨平台的便利（支持windows、Linux、MAC OS 等开发平台，方便跨平台移植），本文选择最新版的SeggerEmbeddedStudio_ARM_v520 开发Nordic 应用。

Nordic nRF52 DK 板载J-Link 模块，J-Link 仿真器也是Segger 公司开发的，因此Segger Embedded Studio 对J-Link 仿真功能的支持也更完善强大。为方便nRF52 BLE 芯片下载调试，还需要安装J-Link 驱动程序，本文选择最新版的 JLink_Windows_V684a。Nordic 对J-Link 驱动程序进行了封装，提供了nrfjprog 命令行工具，本文选择Nordic 封装的命令行工具版本 nRF-Command-Line-Tools_10_10_0_Installer。

本文选择的nRF5 开发工具版本汇总如下（可参考博文：[Nordic nRF52开发环境搭建](https://www.cnblogs.com/iini/p/9043565.html)）：

 - **IDE Toolchain**：Setup_EmbeddedStudio_ARM_v5.20_win_x64
 - **J-Link Driver**：nRF-Command-Line-Tools_10_10_0_Installer_64
 - **nRF5 SDK**：nRF5_SDK_17.0.2_d674dde
 - **SoftDevice(BLE protocol stack)**：s132_nrf52_7.20
 - **Development platform**：Windows 10_x64

# 二、扫码连接功能开发
前言部分已经简单介绍了实现一扫即连功能的原理，一扫即连功能主要在BLE Central 端（也即nRF52 DK）实现，nRF52 DK 一端通过UART 与PC 通信，另一端通过BLE 与从机设备通信，这是典型的蓝牙串口透明传输应用，Nordic 也提供了相应的示例.\nRF5_SDK\examples\ble_central\ble_app_uart_c。

我们可以在ble_app_uart_c 示例的基础上，新增我们需要的一扫即连功能。Nordic 提供的蓝牙透传示例工程主要包括两个部分：UART 应用和BLE NUS (Nordic UART Service)，前者对应上图中的App-Specific peripheral drivers 及其Application，后者对应上图中的nRF SoftDevice 及其Profiles / Services。

![NUS与UART App 通信方式](https://img-blog.csdnimg.cn/20201026171557290.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

我们打开ble_app_uart_c 示例工程文件 .\nRF5_SDK_15.3.0_59ac345\examples\ble_central\ble_app_uart_c\pca10040\s132\ses\ble_app_uart_c_pca10040_s132.emProject，开始了解该示例工程的业务逻辑，并在此基础上新增我们需要的一扫即连功能。在此之前，我们先编译该工程项目，编译无错误，然后通过J-Link 连接nRF52 DK 并将编译文件烧录到开发板中，烧录验证均未报错，说明示例工程代码没问题。

## 2.1 ble_app_uart_c 工程简介
Nordic 提供的ble_app_uart_c 示例工程并没有使用RTOS 实时操作系统，只是一个前后台系统，主要靠中断或事件触发来保证程序的实时性。我们先浏览该示例工程入口主函数的代码：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c

int main(void)
{
    // Initialize.
    log_init();					// Initializes the nrf log module
    timer_init();				// Initializes the app timer
    uart_init();				// Initializes the UART 
    buttons_leds_init();		// Initializes buttons and leds
    db_discovery_init();		// Initializes the database discovery module
    power_management_init();	// Initializes power management module
    ble_stack_init();			// Initializes the SoftDevice and the BLE event interrupt(BLE stack)
    gatt_init();				// Initializes the GATT library
    nus_c_init();				// Initializes the Nordic UART Service (NUS) client
    scan_init();				// Initializes the scanning and setting the filters

    // Start execution.
    printf("BLE UART central example started.\r\n");
    NRF_LOG_INFO("BLE UART central example started.");
    scan_start();				// starting scanning

    // Enter main loop.
    for (;;)
    {
        idle_state_handle();	// Handles any pending log operations, then sleeps until the next event occurs.
    }
}
```

该工程main 函数的前半部分是相关模块的初始化，待涉及的资源初始化完成后，开始执行扫描过程（或设备发现过程），发现周围正在广播的蓝牙从机设备，若发现的从机设备符合蓝牙主机设置的过滤条件，则蓝牙主机向该从机设备发起连接。双方建立连接后，蓝牙主机开始执行服务发现过程，发现从机设备提供的服务（该示例工程中指的是Nordic Uart Service）后，蓝牙主机就可以作为客户端访问从机设备提供的服务了。

最后，main 函数进入主循环，处理空闲状态idle_state_handle，也即当前任务处理完成后进入睡眠状态节省功耗，当检测到有中断或事件触发时，唤醒设备并执行中断服务程序或事件处理程序。

BLE 协议栈比较复杂，涉及的状态也较多，Nordic 使用有限状态机模型来管理蓝牙设备的当前状态及状态切换，当特定事件触发后，根据当前所处的状态，执行相应的事件处理程序。下面给出一个状态机单元供参考（可参考博文：[有限状态机](https://blog.csdn.net/m0_37621078/article/details/90243451)）： 

![有限状态机模型](https://img-blog.csdnimg.cn/20201027141158930.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

## 2.2 GAP(目标设备发现和连接过程)
### 2.2.1 设置并启用过滤器
蓝牙主机上电初始化后，先执行设备发现过程（[Discovery modes and procedures](https://blog.csdn.net/m0_37621078/article/details/107850523#t5)）以发现周围处于广播状态的从机设备（从机设备上电初始化后，执行advertising_start 过程开始对外广播），如果周围有多个处于可发现模式的从机设备，蓝牙主机将扫描出一个设备列表。工程ble_app_uart_c 初始化并执行设备发现过程的代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c

/**@brief Function for initializing the scanning and setting the filters. */
static void scan_init(void)
{
    ret_code_t          err_code;
    nrf_ble_scan_init_t init_scan;

    memset(&init_scan, 0, sizeof(init_scan));

    init_scan.connect_if_match = true;
    init_scan.conn_cfg_tag     = APP_BLE_CONN_CFG_TAG;

    err_code = nrf_ble_scan_init(&m_scan, &init_scan, scan_evt_handler);
    APP_ERROR_CHECK(err_code);

    err_code = nrf_ble_scan_filter_set(&m_scan, SCAN_UUID_FILTER, &m_nus_uuid);
    APP_ERROR_CHECK(err_code);

    err_code = nrf_ble_scan_filters_enable(&m_scan, NRF_BLE_SCAN_UUID_FILTER, false);
    APP_ERROR_CHECK(err_code);
}

/**@brief NUS UUID. */
static ble_uuid_t const m_nus_uuid =
{
    .uuid = BLE_UUID_NUS_SERVICE,
    .type = NUS_SERVICE_UUID_TYPE
};

/**@brief Function to start scanning. */
static void scan_start(void)
{
    ret_code_t ret;

    ret = nrf_ble_scan_start(&m_scan);
    APP_ERROR_CHECK(ret);
	......
}


// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.h
/**@brief Types of filters. */
typedef enum
{
    SCAN_NAME_FILTER,       /**< Filter for names. */
    SCAN_SHORT_NAME_FILTER, /**< Filter for short names. */
    SCAN_ADDR_FILTER,       /**< Filter for addresses. */
    SCAN_UUID_FILTER,       /**< Filter for UUIDs. */
    SCAN_APPEARANCE_FILTER, /**< Filter for appearances. */
} nrf_ble_scan_filter_type_t;
```

在执行扫描过程前，蓝牙主机可以设置过滤条件，抛弃不符合过滤条件的从机设备，在蓝牙主机的发现设备列表中只保留符合过滤条件的设备，比如只保留给定设备名、设备MAC地址、设备服务UUID 等条件的从机设备。原示例工程中选择SCAN_UUID_FILTER（也即BLE_UUID_NUS_SERVICE）作为过滤条件，也即提供NUS 的从机设备都可以被发现，这并不是我们需要的，我们应怎样借助过滤器实现一扫即连功能呢？

我们期望通过扫描MAC 地址自动连接到目标设备，且设备的MAC 地址具有唯一性，我们可以设置过滤条件为SCAN_ADDR_FILTER，也即只有符合给定MAC 地址的从机设备才会被发现。由于符合该过滤条件的目标设备至多一个，可以设置当发现目标设备后，自动连接到该目标设备，这就实现了我们期望的一扫即连功能。因此，我们将上述scan_init 函数的代码修改如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c

/**@brief NUS ADDR. */
uint8_t m_ble_addr[BLE_GAP_ADDR_LEN] = {0x00};

/**@brief Function for initializing the scanning and setting the filters. */
static void scan_init(uint8_t * p_addr)
{
    ret_code_t          err_code;
    nrf_ble_scan_init_t init_scan;

    memset(&init_scan, 0, sizeof(init_scan));

    init_scan.connect_if_match = true;
    init_scan.conn_cfg_tag     = APP_BLE_CONN_CFG_TAG;

    err_code = nrf_ble_scan_init(&m_scan, &init_scan, scan_evt_handler);
    APP_ERROR_CHECK(err_code);
	
    err_code = nrf_ble_scan_filter_set(&m_scan, SCAN_ADDR_FILTER, p_addr);
    APP_ERROR_CHECK(err_code);

    err_code = nrf_ble_scan_filters_enable(&m_scan, NRF_BLE_SCAN_ADDR_FILTER, false);
    APP_ERROR_CHECK(err_code);
}

int main(void)
{
    // Initialize.
    ......
    scan_init(m_ble_addr);		// 设备地址通过参数传入
    
    // Start execution.
    printf("Start scanning the MAC address of the target BLE device.\r\n");
    NRF_LOG_INFO("Start scanning the MAC address of the target BLE device.");
    scan_start();
	......
}
```

我们将扫描过滤条件设置为SCAN_ADDR_FILTER，由于我们初始时不知道目标设备的MAC 地址，新增地址变量m_ble_addr 的初始值设为零。目标设备的地址是PC通过UART 协议传给蓝牙主机的，待蓝牙主机接收到目标设备地址时，其已经完成初始化过程，因此需要使用目标设备地址重新设置过滤条件，上述代码借助函数scan_init 参数传入目标设备地址。

继续看过滤条件设置函数nrf_ble_scan_filter_set 和nrf_ble_scan_filters_enable 实现代码，要添加并使能设备地址过滤条件，还需要配置宏定义NRF_BLE_SCAN_ADDRESS_CNT 大于0，我们只传入一个设备地址，因此将sdk_config.h 文件中定义的宏NRF_BLE_SCAN_ADDRESS_CNT 设置为1。我们不需要添加并使能UUID，因此将宏NRF_BLE_SCAN_UUID_CNT 设置为0，修改后的代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.c

ret_code_t nrf_ble_scan_filter_set(nrf_ble_scan_t     * const p_scan_ctx,
                                   nrf_ble_scan_filter_type_t type,
                                   void const               * p_data)
{
    VERIFY_PARAM_NOT_NULL(p_scan_ctx);
    VERIFY_PARAM_NOT_NULL(p_data);

    switch (type)
    {
#if (NRF_BLE_SCAN_NAME_CNT > 0)
        case SCAN_NAME_FILTER:
        {
            char * p_name = (char *)p_data;
            return nrf_ble_scan_name_filter_add(p_scan_ctx, p_name);
        }
#endif
......
#if (NRF_BLE_SCAN_ADDRESS_CNT > 0)
        case SCAN_ADDR_FILTER:
        {
            uint8_t * p_addr = (uint8_t *)p_data;
            return nrf_ble_scan_addr_filter_add(p_scan_ctx, p_addr);
        }
#endif

#if (NRF_BLE_SCAN_UUID_CNT > 0)
        case SCAN_UUID_FILTER:
        {
            ble_uuid_t * p_uuid = (ble_uuid_t *)p_data;
            return nrf_ble_scan_uuid_filter_add(p_scan_ctx, p_uuid);
        }
#endif
......
        default:
            return NRF_ERROR_INVALID_PARAM;
    }
}


// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\pca10040\s132\config\sdk_config.h
// <e> NRF_BLE_SCAN_FILTER_ENABLE - Enabling filters for the Scanning Module.
//==========================================================
#ifndef NRF_BLE_SCAN_FILTER_ENABLE
#define NRF_BLE_SCAN_FILTER_ENABLE 1
#endif
// <o> NRF_BLE_SCAN_UUID_CNT - Number of filters for UUIDs. 
#ifndef NRF_BLE_SCAN_UUID_CNT
#define NRF_BLE_SCAN_UUID_CNT 0
#endif

// <o> NRF_BLE_SCAN_NAME_CNT - Number of name filters. 
#ifndef NRF_BLE_SCAN_NAME_CNT
#define NRF_BLE_SCAN_NAME_CNT 0
#endif
......
// <o> NRF_BLE_SCAN_ADDRESS_CNT - Number of address filters. 
#ifndef NRF_BLE_SCAN_ADDRESS_CNT
#define NRF_BLE_SCAN_ADDRESS_CNT 1
#endif
......
```

到这里，蓝牙主机扫描过程的过滤条件配置完成。接下来需要解决的问题有两个：一个是如何将目标设备的MAC 地址传给蓝牙主机；另一个是如何配置为扫描到符合过滤条件的目标设备后自动向其发起连接。前一个问题在下文谈到UART 时解决，这里先解决后一个问题。

### 2.2.2 启用匹配即连接功能
在函数scan_init 代码中，为变量 init_scan.connect_if_match 赋值为 true，看字面意思是如果符合过滤条件就发起连接，这个判断是否准确需要我们到数据结构的定义中确认，我们查询结构体类型nrf_ble_scan_init_t 和nrf_ble_scan_t 的数据结构声明如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.h
/**@brief Structure for Scanning Module initialization. */
typedef struct
{
    ble_gap_scan_params_t const * p_scan_param;     /**< BLE GAP scan parameters required to initialize the module. Can be initialized as NULL. If NULL, the parameters required to initialize the module are loaded from the static configuration. */
    bool                          connect_if_match; /**< If set to true, the module automatically connects after a filter match or successful identification of a device from the whitelist. */
    ble_gap_conn_params_t const * p_conn_param;     /**< Connection parameters. Can be initialized as NULL. If NULL, the default static configuration is used. */
    uint8_t                       conn_cfg_tag;     /**< Variable to keep track of what connection settings will be used if a filer match or a whitelist match results in a connection. */
} nrf_ble_scan_init_t;

/**@brief Scan module instance. Options for the different scanning modes.
 * @details This structure stores all module settings. It is used to enable or disable scanning modes and to configure filters. */
typedef struct
{
#if (NRF_BLE_SCAN_FILTER_ENABLE == 1)
    nrf_ble_scan_filters_t scan_filters;                              /**< Filter data. */
#endif
    bool                       connect_if_match;                      /**< If set to true, the module automatically connects after a filter match or successful identification of a device from the whitelist. */
    ble_gap_conn_params_t      conn_params;                           /**< Connection parameters. */
    uint8_t                    conn_cfg_tag;                          /**< Variable to keep track of what connection settings will be used if a filer match or a whitelist match results in a connection. */
    ble_gap_scan_params_t      scan_params;                           /**< GAP scanning parameters. */
    nrf_ble_scan_evt_handler_t evt_handler;                           /**< Handler for the scanning events. Can be initialized as NULL if no handling is implemented in the main application. */
    uint8_t                    scan_buffer_data[NRF_BLE_SCAN_BUFFER]; /**< Buffer where advertising reports will be stored by the SoftDevice. */
    ble_data_t                 scan_buffer;                           /**< Structure-stored pointer to the buffer where advertising reports will be stored by the SoftDevice. */
} nrf_ble_scan_t;


// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.c
ret_code_t nrf_ble_scan_init(nrf_ble_scan_t            * const p_scan_ctx,
                             nrf_ble_scan_init_t const * const p_init,
                             nrf_ble_scan_evt_handler_t        evt_handler)
{
    VERIFY_PARAM_NOT_NULL(p_scan_ctx);

    p_scan_ctx->evt_handler = evt_handler;

#if (NRF_BLE_SCAN_FILTER_ENABLE == 1)
    // Disable all scanning filters.
    memset(&p_scan_ctx->scan_filters, 0, sizeof(p_scan_ctx->scan_filters));
#endif

    // If the pointer to the initialization structure exist, use it to scan the configuration.
    if (p_init != NULL)
    {
        p_scan_ctx->connect_if_match = p_init->connect_if_match;
        p_scan_ctx->conn_cfg_tag     = p_init->conn_cfg_tag;

        if (p_init->p_scan_param != NULL)
        {
            p_scan_ctx->scan_params = *p_init->p_scan_param;
        }
        else
        {
            // Use the default static configuration.
            nrf_ble_scan_default_param_set(p_scan_ctx);
        }

        if (p_init->p_conn_param != NULL)
        {
            p_scan_ctx->conn_params = *p_init->p_conn_param;
        }
        else
        {
            // Use the default static configuration.
            nrf_ble_scan_default_conn_param_set(p_scan_ctx);
        }
    }
    // If pointer is NULL, use the static default configuration.
    else
    {
        nrf_ble_scan_default_param_set(p_scan_ctx);
        nrf_ble_scan_default_conn_param_set(p_scan_ctx);

        p_scan_ctx->connect_if_match = false;
    }

    // Assign a buffer where the advertising reports are to be stored by the SoftDevice.
    p_scan_ctx->scan_buffer.p_data = p_scan_ctx->scan_buffer_data;
    p_scan_ctx->scan_buffer.len    = NRF_BLE_SCAN_BUFFER;

    return NRF_SUCCESS;
}
```

从上述结构体变量connect_if_match 的注释中可以了解到，该成员变量赋值为true 就可以实现扫描到匹配过滤条件的目标设备后，自动向其发起连接，原工程代码的配置已经实现了我们期望的功能，因此不需要再对其修改。

### 2.2.3 设置扫描与连接参数
在函数nrf_ble_scan_init 中，也完成了扫描参数和连接参数的初始化，ble_app_uart_c 工程直接使用了默认的扫描参数与连接参数，通过查看函数nrf_ble_scan_default_param_set 和nrf_ble_scan_default_conn_param_set 的实现代码，发现使用的扫描参数和连接参数来源于sdk_config.h 文件中的宏定义，本文也沿用如下的扫描参数与连接参数（可参考博文：[链路层广播通信与连接通信](https://blog.csdn.net/m0_37621078/article/details/107724799)）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\pca10040\s132\config\sdk_config.h
// <o> NRF_BLE_SCAN_SCAN_INTERVAL - Scanning interval. Determines the scan interval in units of 0.625 millisecond. 
#ifndef NRF_BLE_SCAN_SCAN_INTERVAL
#define NRF_BLE_SCAN_SCAN_INTERVAL 160
#endif

// <o> NRF_BLE_SCAN_SCAN_DURATION - Duration of a scanning session in units of 10 ms. Range: 0x0001 - 0xFFFF (10 ms to 10.9225 ms). If set to 0x0000, the scanning continues until it is explicitly disabled. 
#ifndef NRF_BLE_SCAN_SCAN_DURATION
#define NRF_BLE_SCAN_SCAN_DURATION 0
#endif

// <o> NRF_BLE_SCAN_SCAN_WINDOW - Scanning window. Determines the scanning window in units of 0.625 millisecond. 
#ifndef NRF_BLE_SCAN_SCAN_WINDOW
#define NRF_BLE_SCAN_SCAN_WINDOW 80
#endif

// <o> NRF_BLE_SCAN_MIN_CONNECTION_INTERVAL - Determines minimum connection interval in milliseconds. 
#ifndef NRF_BLE_SCAN_MIN_CONNECTION_INTERVAL
#define NRF_BLE_SCAN_MIN_CONNECTION_INTERVAL 7.5
#endif

// <o> NRF_BLE_SCAN_MAX_CONNECTION_INTERVAL - Determines maximum connection interval in milliseconds. 
#ifndef NRF_BLE_SCAN_MAX_CONNECTION_INTERVAL
#define NRF_BLE_SCAN_MAX_CONNECTION_INTERVAL 30
#endif

// <o> NRF_BLE_SCAN_SLAVE_LATENCY - Determines the slave latency in counts of connection events. 
#ifndef NRF_BLE_SCAN_SLAVE_LATENCY
#define NRF_BLE_SCAN_SLAVE_LATENCY 0
#endif

// <o> NRF_BLE_SCAN_SUPERVISION_TIMEOUT - Determines the supervision time-out in units of 10 millisecond. 
#ifndef NRF_BLE_SCAN_SUPERVISION_TIMEOUT
#define NRF_BLE_SCAN_SUPERVISION_TIMEOUT 4000
#endif
```

这里先假设目标设备地址已经传入并设置为过滤条件，且配置匹配即连接选项（也即connect_if_match = true），我们看Nordic 蓝牙主机如何向目标设备发起并建立连接。

前面已经展示了开始扫描函数scan_start 实际调用的是函数nrf_ble_scan_start，该函数的实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.c
ret_code_t nrf_ble_scan_start(nrf_ble_scan_t const * const p_scan_ctx)
{
    VERIFY_PARAM_NOT_NULL(p_scan_ctx);

    ret_code_t err_code;
    scan_evt_t scan_evt;

    memset(&scan_evt, 0, sizeof(scan_evt));

    nrf_ble_scan_stop();

    // If the whitelist is used and the event handler is not NULL, send the whitelist request to the main application.
    ......
    // Start the scanning.
    err_code = sd_ble_gap_scan_start(&p_scan_ctx->scan_params, &p_scan_ctx->scan_buffer);

    // It is okay to ignore this error, because the scan stopped earlier.
    ......
    return NRF_SUCCESS;
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gap.h
/**@brief Start or continue scanning (GAP Discovery procedure, Observer Procedure).
 * @event{@ref BLE_GAP_EVT_ADV_REPORT, An advertising or scan response packet has been received.}
 * @event{@ref BLE_GAP_EVT_TIMEOUT, Scanner has timed out.} */
SVCALL(SD_BLE_GAP_SCAN_START, uint32_t, sd_ble_gap_scan_start(ble_gap_scan_params_t const *p_scan_params, ble_data_t const * p_adv_report_buffer));
```

函数nrf_ble_scan_start 最终调用的是蓝牙协议栈softdevice 的接口函数sd_ble_gap_scan_start，从该函数的介绍中可知，该函数会开始GAP Discovery procedure。在扫描发现过程中，如果接收到广播报文或扫描响应报文，则会触发BLE_GAP_EVT_ADV_REPORT 事件，若迟迟接收不到任何报文则会触发BLE_GAP_EVT_TIMEOUT 事件。当这些事件发生后，如何继续处理呢？

### 2.2.4 为扫描过程注册事件处理函数
还记得前面介绍的有限状态机吗？在初始化过程中，会为可能发生的事件注册相应的事件处理函数，当某事件发生时会执行相应的事件处理函数，根据当前所处的状态执行特定的响应动作。 

我们为扫描发现过程注册了两个事件处理函数，在前面扫描初始化函数nrf_ble_scan_init 代码中已经注册了一个事件处理函数scan_evt_handler，当协议栈完成扫描过程后会调用该函数通知应用层扫描结果，并根据扫描结果执行后续的响应动作，事件处理函数scan_evt_handler 的实现代码及可能的事件类型如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief Function for handling Scanning Module events.
 */
static void scan_evt_handler(scan_evt_t const * p_scan_evt)
{
    ret_code_t err_code;

    switch(p_scan_evt->scan_evt_id)
    {
         case NRF_BLE_SCAN_EVT_CONNECTING_ERROR:
         {
              err_code = p_scan_evt->params.connecting_err.err_code;
              APP_ERROR_CHECK(err_code);
         } break;

         case NRF_BLE_SCAN_EVT_CONNECTED:
         {
              ble_gap_evt_connected_t const * p_connected =
                               p_scan_evt->params.connected.p_connected;
             // Scan is automatically stopped by the connection.
             ......
         } break;

         case NRF_BLE_SCAN_EVT_SCAN_TIMEOUT:
         {
             NRF_LOG_INFO("Scan timed out.");
             scan_start();
         } break;

         default:
             break;
    }
}

// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.h
/**@brief Enumeration for scanning events.
 * @details These events are propagated to the main application if a handler is provided during the initialization of the Scanning Module. 
 *          @ref NRF_BLE_SCAN_EVT_WHITELIST_REQUEST cannot be ignored if whitelist is used. */
typedef enum
{
    NRF_BLE_SCAN_EVT_FILTER_MATCH,         /**< A filter is matched or all filters are matched in the multifilter mode. */
    NRF_BLE_SCAN_EVT_WHITELIST_REQUEST,    /**< Request the whitelist from the main application. For whitelist scanning to work, the whitelist must be set when this event occurs. */
    NRF_BLE_SCAN_EVT_WHITELIST_ADV_REPORT, /**< Send notification to the main application when a device from the whitelist is found. */
    NRF_BLE_SCAN_EVT_NOT_FOUND,            /**< The filter was not matched for the scan data. */
    NRF_BLE_SCAN_EVT_SCAN_TIMEOUT,         /**< Scan timeout. */
    NRF_BLE_SCAN_EVT_CONNECTING_ERROR,     /**< Error occurred when establishing the connection. In this event, an error is passed from the function call @ref sd_ble_gap_connect. */
    NRF_BLE_SCAN_EVT_CONNECTED             /**< Connected to device. */
} nrf_ble_scan_evt_t;
```

在扫描发现过程中，向蓝牙协议栈注册的另一个事件处理函数nrf_ble_scan_on_ble_evt 是借助宏定义实现的。通过宏NRF_BLE_SCAN_DEF 定义数据类型为nrf_ble_scan_t 的变量m_scan（前面介绍的函数scan_init 主要就是对变量m_scan 进行初始化配置），并通过宏NRF_SDH_BLE_OBSERVER 向BLE 协议栈softdevice 注册事件处理函数nrf_ble_scan_on_ble_evt，并把前面定义的变量m_scan 作为参数传入。扫描事件处理函数nrf_ble_scan_on_ble_evt 的注册过程如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
NRF_BLE_SCAN_DEF(m_scan);                                               /**< Scanning Module instance. */

// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.h
/**@brief Macro for defining a nrf_ble_scan instance.
 * @param   _name   Name of the instance. */
#define NRF_BLE_SCAN_DEF(_name)                            \
    static nrf_ble_scan_t _name;                           \
    NRF_SDH_BLE_OBSERVER(_name ## _ble_obs,                \
                         NRF_BLE_SCAN_OBSERVER_PRIO,       \
                         nrf_ble_scan_on_ble_evt, &_name); \

// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\common\nrf_sdh_ble.h
/**@brief   Macro for registering @ref nrf_sdh_soc_evt_observer_t. Modules that want to be
 *          notified about SoC events must register the handler using this macro.
 * @details This macro places the observer in a section named "sdh_soc_observers".
 *
 * @param[in]   _name       Observer name.
 * @param[in]   _prio       Priority of the observer event handler. The smaller the number, the higher the priority.
 * @param[in]   _handler    BLE event handler.
 * @param[in]   _context    Parameter to the event handler. */
#define NRF_SDH_BLE_OBSERVER(_name, _prio, _handler, _context)                                      \
STATIC_ASSERT(NRF_SDH_BLE_ENABLED, "NRF_SDH_BLE_ENABLED not set!");                                 \
STATIC_ASSERT(_prio < NRF_SDH_BLE_OBSERVER_PRIO_LEVELS, "Priority level unavailable.");             \
NRF_SECTION_SET_ITEM_REGISTER(sdh_ble_observers, _prio, static nrf_sdh_ble_evt_observer_t _name) =  \
{                                                                                                   \
    .handler   = _handler,                                                                          \
    .p_context = _context                                                                           \
}

// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.c
void nrf_ble_scan_on_ble_evt(ble_evt_t const * p_ble_evt, void * p_contex)
{
    nrf_ble_scan_t                 * p_scan_data  = (nrf_ble_scan_t *)p_contex;
    ble_gap_evt_adv_report_t const * p_adv_report = &p_ble_evt->evt.gap_evt.params.adv_report;
    ble_gap_evt_t const            * p_gap_evt    = &p_ble_evt->evt.gap_evt;

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_ADV_REPORT:
            nrf_ble_scan_on_adv_report(p_scan_data, p_adv_report);
            break;

        case BLE_GAP_EVT_TIMEOUT:
            nrf_ble_scan_on_timeout(p_scan_data, p_gap_evt);
            break;

        case BLE_GAP_EVT_CONNECTED:
            nrf_ble_scan_on_connected_evt(p_scan_data, p_gap_evt);
            break;

        default:
            break;
    }
}
```

前面谈到调用函数sd_ble_gap_scan_start 开始GAP Discovery procedure 后，若接收到周围的广播报文，则会触发BLE_GAP_EVT_ADV_REPORT 事件。我们通过宏NRF_SDH_BLE_OBSERVER 向Nordic 蓝牙协议栈softdevice 注册了扫描事件处理函数nrf_ble_scan_on_ble_evt，当softdevice 触发扫描事件时便会执行注册的扫描事件处理函数nrf_ble_scan_on_ble_evt，并根据事件类型选择后续的响应动作。假设蓝牙主机softdevice 触发了BLE_GAP_EVT_ADV_REPORT 事件，则在扫描事件处理函数中执行函数nrf_ble_scan_on_adv_report，该函数的实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.c
/**@brief Function for calling the BLE_GAP_EVT_ADV_REPORT event to check whether the received scanning data matches the scan configuration.
 * @param[in] p_scan_ctx    Pointer to the Scanning Module instance.
 * @param[in] p_adv_report  Advertising report. */
static void nrf_ble_scan_on_adv_report(nrf_ble_scan_t           const * const p_scan_ctx,
                                       ble_gap_evt_adv_report_t const * const p_adv_report)
{
    scan_evt_t scan_evt;

#if (NRF_BLE_SCAN_FILTER_ENABLE == 1)
    uint8_t filter_cnt       = 0;
    uint8_t filter_match_cnt = 0;
#endif

    memset(&scan_evt, 0, sizeof(scan_evt));

    scan_evt.p_scan_params = &p_scan_ctx->scan_params;

    // If the whitelist is used, do not check the filters and return.
    ......
#if (NRF_BLE_SCAN_FILTER_ENABLE == 1)
    bool const all_filter_mode   = p_scan_ctx->scan_filters.all_filters_mode;
    bool       is_filter_matched = false;

#if (NRF_BLE_SCAN_ADDRESS_CNT > 0)
    bool const addr_filter_enabled = p_scan_ctx->scan_filters.addr_filter.addr_filter_enabled;
#endif
......
#if (NRF_BLE_SCAN_ADDRESS_CNT > 0)
    // Check the address filter.
    if (addr_filter_enabled)
    {
        // Number of active filters.
        filter_cnt++;
        if (adv_addr_compare(p_adv_report, p_scan_ctx))
        {
            // Number of filters matched.
            filter_match_cnt++;
            // Information about the filters matched.
            scan_evt.params.filter_match.filter_match.address_filter_match = true;
            is_filter_matched = true;
        }
    }
#endif
......
    scan_evt.params.filter_match.p_adv_report = p_adv_report;

    // In the multifilter mode, the number of the active filters must equal the number of the filters matched to generate the notification.
    if (all_filter_mode && (filter_match_cnt == filter_cnt))
    {
        scan_evt.scan_evt_id = NRF_BLE_SCAN_EVT_FILTER_MATCH;
        nrf_ble_scan_connect_with_target(p_scan_ctx, p_adv_report);
    }
    // In the normal filter mode, only one filter match is needed to generate the notification to the main application.
    else if ((!all_filter_mode) && is_filter_matched)
    {
        scan_evt.scan_evt_id = NRF_BLE_SCAN_EVT_FILTER_MATCH;
        nrf_ble_scan_connect_with_target(p_scan_ctx, p_adv_report);
    }
    else
    {
        scan_evt.scan_evt_id        = NRF_BLE_SCAN_EVT_NOT_FOUND;
        scan_evt.params.p_not_found = p_adv_report;

    }

    // If the event handler is not NULL, notify the main application.
    if (p_scan_ctx->evt_handler != NULL)
    {
        p_scan_ctx->evt_handler(&scan_evt);
    }

#endif // NRF_BLE_SCAN_FILTER_ENABLE

    // Resume the scanning.
    UNUSED_RETURN_VALUE(sd_ble_gap_scan_start(NULL, &p_scan_ctx->scan_buffer));
}
```

函数nrf_ble_scan_on_adv_report 会将接收到的广播报文中广播者的设备信息与蓝牙主机设置的过滤条件相比较，如果该广播者匹配过滤条件，则判断其为目标设备，将调用函数nrf_ble_scan_connect_with_target 向目标设备发起连接。最后，该函数会调用应用层扫描事件处理函数scan_evt_handler（由函数nrf_ble_scan_init 注册），并根据触发的扫描事件类型执行用户预设的响应动作。

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_scan\nrf_ble_scan.c
/**@brief Function for establishing the connection with a device. */
static void nrf_ble_scan_connect_with_target(nrf_ble_scan_t           const * const p_scan_ctx,
                                             ble_gap_evt_adv_report_t const * const p_adv_report)
{
    ......
    // Return if the automatic connection is disabled.
    if (!p_scan_ctx->connect_if_match)
    {
        return;
    }

    // Stop scanning.
    nrf_ble_scan_stop();

    memset(&scan_evt, 0, sizeof(scan_evt));

    // Establish connection.
    err_code = sd_ble_gap_connect(p_addr, p_scan_params, p_conn_params, con_cfg_tag);

    NRF_LOG_DEBUG("Connecting");

    scan_evt.scan_evt_id                    = NRF_BLE_SCAN_EVT_CONNECTING_ERROR;
    scan_evt.params.connecting_err.err_code = err_code;

    NRF_LOG_DEBUG("Connection status: %d", err_code);

    // If an error occurred, send an event to the event handler.
    if ((err_code != NRF_SUCCESS) && (p_scan_ctx->evt_handler != NULL))
    {
        p_scan_ctx->evt_handler(&scan_evt);
    }
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gap.h
/**@brief Create a connection (GAP Link Establishment).
 * @event{@ref BLE_GAP_EVT_CONNECTED, A connection was established.}
 * @event{@ref BLE_GAP_EVT_TIMEOUT, Failed to establish a connection.} */
SVCALL(SD_BLE_GAP_CONNECT, uint32_t, sd_ble_gap_connect(ble_gap_addr_t const *p_peer_addr, ble_gap_scan_params_t const *p_scan_params, ble_gap_conn_params_t const *p_conn_params, uint8_t conn_cfg_tag));
```

蓝牙主机通过执行函数nrf_ble_scan_connect_with_target 向目标设备发起连接，实际调用的是Nordic 蓝牙协议栈softdevice 接口函数sd_ble_gap_connect。如果连接建立成功，则会触发BLE_GAP_EVT_CONNECTED 事件，如果连接建立失败，则会触发BLE_GAP_EVT_TIMEOUT 事件，对应的事件处理函数则由蓝牙协议栈初始化函数ble_stack_init 注册到协议栈中。

蓝牙主机与目标从机设备成功建立连接后，就可以开始通信了。如果连接双方有加密通信的需求，接下来需要完成配对甚至绑定过程（本文无此过程）。如果从机设备提供了某些服务services 或profiles，蓝牙主机需要先发现这些服务，才能访问对应的服务，这个过程将在下文介绍。

## 2.3 GATT(NUS服务发现和交互过程)
### 2.3.1 BLE 协议栈初始化
前面介绍了，蓝牙主机扫描到目标设备后，向其发起连接，双方连接建立成功后，蓝牙协议栈会触发BLE_GAP_EVT_CONNECTED 事件，该事件的处理函数是如何被实现并注册的呢？

蓝牙连接过程也会向协议栈注册两个事件处理函数，一个是在蓝牙协议栈初始化函数ble_stack_init 中注册的事件处理函数ble_evt_handler，注册过程实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief Function for initializing the BLE stack.
 * @details Initializes the SoftDevice and the BLE event interrupt. */
static void ble_stack_init(void)
{
    ret_code_t err_code;

    err_code = nrf_sdh_enable_request();
    APP_ERROR_CHECK(err_code);

    // Configure the BLE stack using the default settings.
    // Fetch the start address of the application RAM.
    uint32_t ram_start = 0;
    err_code = nrf_sdh_ble_default_cfg_set(APP_BLE_CONN_CFG_TAG, &ram_start);
    APP_ERROR_CHECK(err_code);

    // Enable BLE stack.
    err_code = nrf_sdh_ble_enable(&ram_start);
    APP_ERROR_CHECK(err_code);

    // Register a handler for BLE events.
    NRF_SDH_BLE_OBSERVER(m_ble_observer, APP_BLE_OBSERVER_PRIO, ble_evt_handler, NULL);
}

/**@brief Function for handling BLE events.
 * @param[in]   p_ble_evt   Bluetooth stack event.
 * @param[in]   p_context   Unused. */
static void ble_evt_handler(ble_evt_t const * p_ble_evt, void * p_context)
{
    ret_code_t            err_code;
    ble_gap_evt_t const * p_gap_evt = &p_ble_evt->evt.gap_evt;

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_CONNECTED:
            err_code = ble_nus_c_handles_assign(&m_ble_nus_c, p_ble_evt->evt.gap_evt.conn_handle, NULL);
            APP_ERROR_CHECK(err_code);

            err_code = bsp_indication_set(BSP_INDICATE_CONNECTED);
            APP_ERROR_CHECK(err_code);

            // start discovery of services. The NUS Client waits for a discovery result
            err_code = ble_db_discovery_start(&m_db_disc, p_ble_evt->evt.gap_evt.conn_handle);
            APP_ERROR_CHECK(err_code);
            break;

        case BLE_GAP_EVT_DISCONNECTED:
            ......
            break;

        case BLE_GAP_EVT_TIMEOUT:
            ......
            break;

        case BLE_GAP_EVT_SEC_PARAMS_REQUEST:
            // Pairing not supported.
            ......
            break;

        case BLE_GAP_EVT_CONN_PARAM_UPDATE_REQUEST:
            // Accepting parameters requested by peer.
            ......
            break;

        case BLE_GAP_EVT_PHY_UPDATE_REQUEST:
        	// Initiate or respond to a PHY Update Procedure.
        	......
        	break;

        case BLE_GATTC_EVT_TIMEOUT:
            // Disconnect on GATT Client timeout event.
            ......
            break;

        case BLE_GATTS_EVT_TIMEOUT:
            // Disconnect on GATT Server timeout event.
            ......
            break;

        default:
            break;
    }
}
```

蓝牙协议栈softdevice 触发连接成功事件BLE_GAP_EVT_CONNECTED 后，先为NUS 服务分配连接句柄，然后开始服务发现过程，以便发现连接的从机设备提供了哪些服务。

### 2.3.2 配置MTU 交换过程
蓝牙主机在进行服务发现前，一般先完成服务配置过程，也即MTU(Maximum Transmission Unit) 交换过程（可参考博文：[GATT feature and procedure](https://blog.csdn.net/m0_37621078/article/details/108391261#t7)），该过程也是在双方建立连接后开始的。借助宏NRF_BLE_GATT_DEF 定义全局变量m_gatt，并向BLE 协议栈注册事件处理函数nrf_ble_gatt_on_ble_evt（与前面介绍的扫描过程变量m_scan 定义和事件处理函数nrf_ble_scan_on_ble_evt 注册过程类似），该事件处理函数的注册过程代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
NRF_BLE_GATT_DEF(m_gatt);                                               /**< GATT module instance. */


// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_gatt\nrf_ble_gatt.h
/**@brief   Macro for defining a nrf_ble_gatt instance.
 * @param   _name   Name of the instance. */
#define NRF_BLE_GATT_DEF(_name)                                                                     \
static nrf_ble_gatt_t _name;                                                                        \
NRF_SDH_BLE_OBSERVER(_name ## _obs,                                                                 \
                     NRF_BLE_GATT_BLE_OBSERVER_PRIO,                                                \
                     nrf_ble_gatt_on_ble_evt, &_name)


// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_gatt\nrf_ble_gatt.c
void nrf_ble_gatt_on_ble_evt(ble_evt_t const * p_ble_evt, void * p_context)
{
    nrf_ble_gatt_t * p_gatt      = (nrf_ble_gatt_t *)p_context;
    uint16_t         conn_handle = p_ble_evt->evt.common_evt.conn_handle;

    if (conn_handle >= NRF_BLE_GATT_LINK_COUNT)
    {
        return;
    }

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_CONNECTED:
        	// Begins an ATT MTU exchange procedure, followed by a data length update request as necessary.
            on_connected_evt(p_gatt, p_ble_evt);
            break;

        case BLE_GAP_EVT_DISCONNECTED:
            on_disconnected_evt(p_gatt, p_ble_evt);
            break;

        case BLE_GATTC_EVT_EXCHANGE_MTU_RSP:
            on_exchange_mtu_rsp_evt(p_gatt, p_ble_evt);
            break;

        case BLE_GATTS_EVT_EXCHANGE_MTU_REQUEST:
            on_exchange_mtu_request_evt(p_gatt, p_ble_evt);
            break;
		......
        default:
            break;
    }

    if (p_gatt->links[conn_handle].att_mtu_exchange_pending)
    {
        ret_code_t err_code;

        err_code = sd_ble_gattc_exchange_mtu_request(conn_handle, p_gatt->links[conn_handle].att_mtu_desired);
        ......
    }
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gattc.h
/**@brief Start an ATT_MTU exchange by sending an Exchange MTU Request to the server.
 * @event{@ref BLE_GATTC_EVT_EXCHANGE_MTU_RSP} */
SVCALL(SD_BLE_GATTC_EXCHANGE_MTU_REQUEST, uint32_t, sd_ble_gattc_exchange_mtu_request(uint16_t conn_handle, uint16_t client_rx_mtu));
```

当softdevie 协议栈触发连接事件BLE_GAP_EVT_CONNECTED 后，GATT 事件处理函数nrf_ble_gatt_on_ble_evt 也会被执行，并调用函数on_connected_evt，如果双方有MTU 交换需求则通过执行函数sd_ble_gattc_exchange_mtu_request 向对端设备发起MTU 交换请求。

如果GATT Client（也即蓝牙主机）确实向GATT Server（也即从机设备）发起了MTU 交换请求，而且GATT Server 接受并响应了MTU 交换请求，GATT Client 在更新MTU 后会触发NRF_BLE_GATT_EVT_ATT_MTU_UPDATED 事件，并执行相应的事件处理函数gatt_evt_handler。

完成MTU 交换后应通知应用层，其处理的最大数据长度SDU(Service Data Unit)也需要同步更新（也即下文代码中的m_ble_nus_max_data_len 变量值），这个事件处理函数gatt_evt_handler 在GATT 模块初始化函数gatt_init 中被注册，实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
static uint16_t m_ble_nus_max_data_len = BLE_GATT_ATT_MTU_DEFAULT - OPCODE_LENGTH - HANDLE_LENGTH; /**< Maximum length of data (in bytes) that can be transmitted to the peer by the Nordic UART service module. */

/**@brief Function for initializing the GATT library. */
void gatt_init(void)
{
    ret_code_t err_code;

    err_code = nrf_ble_gatt_init(&m_gatt, gatt_evt_handler);
    APP_ERROR_CHECK(err_code);

    err_code = nrf_ble_gatt_att_mtu_central_set(&m_gatt, NRF_SDH_BLE_GATT_MAX_MTU_SIZE);
    APP_ERROR_CHECK(err_code);
}

/**@brief Function for handling events from the GATT library. */
void gatt_evt_handler(nrf_ble_gatt_t * p_gatt, nrf_ble_gatt_evt_t const * p_evt)
{
    if (p_evt->evt_id == NRF_BLE_GATT_EVT_ATT_MTU_UPDATED)
    {
        NRF_LOG_INFO("ATT MTU exchange completed.");

        m_ble_nus_max_data_len = p_evt->params.att_mtu_effective - OPCODE_LENGTH - HANDLE_LENGTH;
        NRF_LOG_INFO("Ble NUS max data length set to 0x%X(%d)", m_ble_nus_max_data_len, m_ble_nus_max_data_len);
    }
}
```

### 2.3.3 NUS 服务发现过程
继续看前面介绍的连接事件处理函数ble_evt_handler 代码，当蓝牙主机与从机设备成功建立连接后，协议栈softdevice 触发事件BLE_GAP_EVT_CONNECTED，事件处理函数ble_evt_handler 则会执行函数ble_db_discovery_start 开始服务发现过程，该过程的函数调用逻辑如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_db_discovery\ble_db_discovery.c
uint32_t ble_db_discovery_start(ble_db_discovery_t * const p_db_discovery, uint16_t conn_handle)
{
    ......
    return discovery_start(p_db_discovery, conn_handle);
}

static uint32_t discovery_start(ble_db_discovery_t * const p_db_discovery, uint16_t conn_handle)
{
    ret_code_t          err_code;
    ble_gatt_db_srv_t * p_srv_being_discovered;
    nrf_ble_gq_req_t    db_srv_disc_req;

    memset(p_db_discovery, 0x00, sizeof(ble_db_discovery_t));
    memset(&db_srv_disc_req, 0x00, sizeof(nrf_ble_gq_req_t));

    err_code = nrf_ble_gq_conn_handle_register(mp_gatt_queue, conn_handle);
    VERIFY_SUCCESS(err_code);
    ......
    p_srv_being_discovered = &(p_db_discovery->services[p_db_discovery->curr_srv_ind]);
    p_srv_being_discovered->srv_uuid = m_registered_handlers[p_db_discovery->curr_srv_ind];

    db_srv_disc_req.type                               = NRF_BLE_GQ_REQ_SRV_DISCOVERY;
    db_srv_disc_req.params.gattc_srv_disc.start_handle = SRV_DISC_START_HANDLE;
    db_srv_disc_req.params.gattc_srv_disc.srvc_uuid    = p_srv_being_discovered->srv_uuid;
    db_srv_disc_req.error_handler.p_ctx                = p_db_discovery;
    db_srv_disc_req.error_handler.cb                   = discovery_error_handler;

    err_code = nrf_ble_gq_item_add(mp_gatt_queue, &db_srv_disc_req, conn_handle);

    if (err_code == NRF_SUCCESS)
    {
        p_db_discovery->discovery_in_progress = true;
    }

    return err_code;
}


// .\nRF5_SDK_17.0.2_d674dde\components\ble\nrf_ble_gq\nrf_ble_gq.c
ret_code_t nrf_ble_gq_item_add(nrf_ble_gq_t const * const p_gatt_queue,
                               nrf_ble_gq_req_t   * const p_req,
                               uint16_t                   conn_handle)
{
    ......
    // Purge queues that are no longer used by any connection.
    queues_purge(p_gatt_queue);
    // Check if connection handle is registered and if GATT request is valid.
    ......
    // Try processing a request without buffering.
    if (nrf_queue_is_empty(&p_gatt_queue->p_req_queue[conn_id]))
    {
        bool req_processed = request_process(p_req, conn_handle);
        if (req_processed)
            return err_code;
    }
    // Prepare request for buffering and add it to the queue.
    if (m_req_data_alloc[p_req->type] != NULL)
    {
        VERIFY_PARAM_NOT_NULL(p_gatt_queue->p_data_pool);

        err_code = m_req_data_alloc[p_req->type](p_gatt_queue->p_data_pool, p_req);
        VERIFY_SUCCESS(err_code);
    }
    
    err_code = nrf_queue_push(&p_gatt_queue->p_req_queue[conn_id], p_req);
    ......
    // Check if Softdevice is still busy.
    queue_process(&p_gatt_queue->p_req_queue[conn_id], conn_handle);
    return err_code;
}

/**@brief Function processes subsequent requests from the BGQ instance queue.
 * @param[in] p_queue      Pointer to the queue instance.
 * @param[in] conn_handle  Connection handle. */
static void queue_process(nrf_queue_t const * const p_queue, uint16_t conn_handle)
{
    ret_code_t       err_code;
    nrf_ble_gq_req_t ble_req;

    NRF_LOG_DEBUG("Processing the request queue...");

    err_code = nrf_queue_peek(p_queue, &ble_req);
    if (err_code == NRF_SUCCESS) // Queue is not empty
    {
        switch (ble_req.type)
        {
            case NRF_BLE_GQ_REQ_GATTC_READ:
                NRF_LOG_DEBUG("GATTC Read Request");
                err_code = sd_ble_gattc_read(conn_handle,
                                             ble_req.params.gattc_read.handle,
                                             ble_req.params.gattc_read.offset);
                break;

            case NRF_BLE_GQ_REQ_GATTC_WRITE:
            {
                uint8_t write_data[NRF_BLE_GQ_GATTC_WRITE_MAX_DATA_LEN];

                // Retrieve allocated data.
                ble_req.params.gattc_write.p_value = write_data;
                nrf_memobj_read(ble_req.p_mem_obj,
                                (void *) ble_req.params.gattc_write.p_value,
                                ble_req.params.gattc_write.len, 0);

                NRF_LOG_DEBUG("GATTC Write Request");
                err_code = sd_ble_gattc_write(conn_handle,
                                              &ble_req.params.gattc_write);
            } break;

            case NRF_BLE_GQ_REQ_SRV_DISCOVERY:
            {
                NRF_LOG_DEBUG("GATTC Primary Service Discovery Request");
                err_code = sd_ble_gattc_primary_services_discover(conn_handle,
                                                                  ble_req.params.gattc_srv_disc.start_handle,
                                                                  &ble_req.params.gattc_srv_disc.srvc_uuid);
            } break;

            case NRF_BLE_GQ_REQ_CHAR_DISCOVERY:
            {
                NRF_LOG_DEBUG("GATTC Characteristic Discovery Request");
                err_code = sd_ble_gattc_characteristics_discover(conn_handle,
                                                                 &ble_req.params.gattc_char_disc);
            } break;

            case NRF_BLE_GQ_REQ_DESC_DISCOVERY:
            {
                NRF_LOG_DEBUG("GATTC Characteristic Descriptor Discovery Request")
                err_code = sd_ble_gattc_descriptors_discover(conn_handle,
                                                             &ble_req.params.gattc_desc_disc);
            } break;

            case NRF_BLE_GQ_REQ_GATTS_HVX:
            {
                uint8_t  hvx_data[NRF_BLE_GQ_GATTS_HVX_MAX_DATA_LEN];
                uint16_t len;
                uint16_t hvx_len;

                // Retrieve allocated data.
                ble_req.params.gatts_hvx.p_data = hvx_data;
                nrf_memobj_read(ble_req.p_mem_obj,
                                (void *) &hvx_len,
                                sizeof(uint16_t),
                                0);
                ble_req.params.gatts_hvx.p_len = &hvx_len;
                nrf_memobj_read(ble_req.p_mem_obj,
                                (void *) ble_req.params.gatts_hvx.p_data,
                                *ble_req.params.gatts_hvx.p_len,
                                sizeof(uint16_t));

                len = hvx_len;

                NRF_LOG_DEBUG("GATTS HVX");
                err_code = sd_ble_gatts_hvx(conn_handle,
                                            &ble_req.params.gatts_hvx);

                if ((err_code == NRF_SUCCESS) &&
                    (len != hvx_len))
                {
                    err_code = NRF_ERROR_DATA_SIZE;
                }
            } break;

            default:
                NRF_LOG_WARNING("Unimplemented GATT Request");
                break;
        }

        if (err_code == NRF_ERROR_BUSY) // Softdevice is processing another GATT request.
        {
            NRF_LOG_DEBUG("SD is currently busy. The GATT request procedure will be attempted \
                          again later.");
        }
        else
        {
            // Remove last request descriptor from the queue and free data associated with it.
            if (m_req_data_alloc[ble_req.type] != NULL)
            {
                nrf_memobj_free(ble_req.p_mem_obj);
                NRF_LOG_DEBUG("Pointer to freed memory block: %p.", ble_req.p_mem_obj);
            }
            UNUSED_RETURN_VALUE(nrf_queue_pop(p_queue, &ble_req));

            request_err_code_handle(&ble_req, conn_handle, err_code);
        }
    }
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gattc.h
/**@brief Initiate or continue a GATT Primary Service Discovery procedure.
 * @event{@ref BLE_GATTC_EVT_PRIM_SRVC_DISC_RSP} */
SVCALL(SD_BLE_GATTC_PRIMARY_SERVICES_DISCOVER, uint32_t, sd_ble_gattc_primary_services_discover(uint16_t conn_handle, uint16_t start_handle, ble_uuid_t const *p_srvc_uuid));
```

从上面的代码逻辑可以看到，蓝牙主机的服务发现请求是放到一个队列里面管理的。当有新的服务发现请求时，就将其添加到GATT 队列mp_gatt_queue 中暂存，待协议栈softdevice 空闲时，则从GATT 队列中取出一个服务发现请求进行处理（见函数queue_process 代码）。服务发现请求的类型为NRF_BLE_GQ_REQ_SRV_DISCOVERY，执行到函数queue_process 则调用协议栈接口函数sd_ble_gattc_primary_services_discover 初始化一个GATT 主服务发现过程。GATT Client 发现GATT Server 公开的主服务后，将会触发事件BLE_GATTC_EVT_PRIM_SRVC_DISC_RSP，执行服务发现模块注册的事件处理函数。

由哪个事件处理函数来处理GATT Client 发现公开的主服务后触发的BLE_GATTC_EVT_PRIM_SRVC_DISC_RSP 事件呢？该事件属于服务发现模块，自然由服务发现模块在初始化过程中向协议栈注册的事件处理函数来处理该事件。服务发现模块也注册了两个事件处理函数，注册过程代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
BLE_DB_DISCOVERY_DEF(m_db_disc);                                        /**< Database discovery module instance. */

/** @brief Function for initializing the database discovery module. */
static void db_discovery_init(void)
{
    ble_db_discovery_init_t db_init;

    memset(&db_init, 0, sizeof(ble_db_discovery_init_t));

    db_init.evt_handler  = db_disc_handler;
    db_init.p_gatt_queue = &m_ble_gatt_queue;

    ret_code_t err_code = ble_db_discovery_init(&db_init);
    APP_ERROR_CHECK(err_code);
}

// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_db_discovery\ble_db_discovery.h
/**@brief Macro for defining a ble_db_discovery instance. */
#define BLE_DB_DISCOVERY_DEF(_name)                                                                 \
static ble_db_discovery_t _name = {.discovery_in_progress = 0,                                      \
                                   .conn_handle           = BLE_CONN_HANDLE_INVALID};               \
NRF_SDH_BLE_OBSERVER(_name ## _obs,                                                                 \
                     BLE_DB_DISC_BLE_OBSERVER_PRIO,                                                 \
                     ble_db_discovery_on_ble_evt, &_name)


// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_db_discovery\ble_db_discovery.c
void ble_db_discovery_on_ble_evt(ble_evt_t const * p_ble_evt,
                                 void            * p_context)
{
    VERIFY_PARAM_NOT_NULL_VOID(p_ble_evt);
    VERIFY_PARAM_NOT_NULL_VOID(p_context);
    VERIFY_MODULE_INITIALIZED_VOID();

    ble_db_discovery_t * p_db_discovery = (ble_db_discovery_t *)p_context;

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GATTC_EVT_PRIM_SRVC_DISC_RSP:
            on_primary_srv_discovery_rsp(p_db_discovery, &(p_ble_evt->evt.gattc_evt));
            break;

        case BLE_GATTC_EVT_CHAR_DISC_RSP:
            on_characteristic_discovery_rsp(p_db_discovery, &(p_ble_evt->evt.gattc_evt));
            break;

        case BLE_GATTC_EVT_DESC_DISC_RSP:
            on_descriptor_discovery_rsp(p_db_discovery, &(p_ble_evt->evt.gattc_evt));
            break;

        case BLE_GAP_EVT_DISCONNECTED:
            on_disconnected(p_db_discovery, &(p_ble_evt->evt.gap_evt));
            break;

        default:
            break;
    }
}

/**@brief     Function for handling primary service discovery response.
 * @param[in] p_db_discovery    Pointer to the DB Discovery structure.
 * @param[in] p_ble_gattc_evt   Pointer to the GATT Client event. */
static void on_primary_srv_discovery_rsp(ble_db_discovery_t       * p_db_discovery,
                                         ble_gattc_evt_t    const * p_ble_gattc_evt)
{
    ......
    if (p_ble_gattc_evt->gatt_status == BLE_GATT_STATUS_SUCCESS)
    {
        ......
        err_code = characteristics_discover(p_db_discovery, p_ble_gattc_evt->conn_handle);
        ......
    }
    else
    {
        // Trigger Service Not Found event to the application.
        discovery_complete_evt_trigger(p_db_discovery, false, p_ble_gattc_evt->conn_handle);
        on_srv_disc_completion(p_db_discovery, p_ble_gattc_evt->conn_handle);
    }
}
```

服务发现模块向协议栈softdevice 注册了事件处理函数ble_db_discovery_on_ble_evt，在应用层由初始化函数db_discovery_init 注册了事件处理函数db_disc_handler。前者主要处理协议栈softdevice 触发的与服务发现相关的事件，后者在服务发现过程完成后，用于通知应用层服务发现结果，应用层根据结果执行后续的响应动作。

GATT Client 协议栈发现主服务后触发事件BLE_GATTC_EVT_PRIM_SRVC_DISC_RSP，并执行注册的事件处理函数ble_db_discovery_on_ble_evt，根据事件类型调用函数on_primary_srv_discovery_rsp 执行响应动作。

主服务发现过程处理完成后，继续调用函数characteristics_discover 开始特征发现过程，特征发现请求也是放到GATT 队列（mp_gatt_queue）内管理的，整个过程跟前面介绍的主服务发现过程类似，只不过选择执行函数queue_process 内的NRF_BLE_GQ_REQ_CHAR_DISCOVERY 事件分支。特征发现过程处理完成后，继续调用函数descriptors_discover 开始描述符发现过程，整个过程也跟前两者类似，这里就不再赘述了。

### 2.3.4 NUS 服务访问过程
待服务发现过程完成后，会在函数on_srv_disc_completion 中调用由db_discovery_init 注册了事件处理函数db_disc_handler，执行后续的响应动作，该函数实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief Function for handling database discovery events.
 * @param[in] p_event  Pointer to the database discovery event. */
static void db_disc_handler(ble_db_discovery_evt_t * p_evt)
{
    ble_nus_c_on_db_disc_evt(&m_ble_nus_c, p_evt);
}


// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_services\ble_nus_c\ble_nus_c.c
void ble_nus_c_on_db_disc_evt(ble_nus_c_t * p_ble_nus_c, ble_db_discovery_evt_t * p_evt)
{
    ble_nus_c_evt_t nus_c_evt;
    memset(&nus_c_evt,0,sizeof(ble_nus_c_evt_t));

    ble_gatt_db_char_t * p_chars = p_evt->params.discovered_db.charateristics;

    // Check if the NUS was discovered.
    if (    (p_evt->evt_type == BLE_DB_DISCOVERY_COMPLETE)
        &&  (p_evt->params.discovered_db.srv_uuid.uuid == BLE_UUID_NUS_SERVICE)
        &&  (p_evt->params.discovered_db.srv_uuid.type == p_ble_nus_c->uuid_type))
    {
        for (uint32_t i = 0; i < p_evt->params.discovered_db.char_count; i++)
        {
            switch (p_chars[i].characteristic.uuid.uuid)
            {
                case BLE_UUID_NUS_RX_CHARACTERISTIC:
                    nus_c_evt.handles.nus_rx_handle = p_chars[i].characteristic.handle_value;
                    break;

                case BLE_UUID_NUS_TX_CHARACTERISTIC:
                    nus_c_evt.handles.nus_tx_handle = p_chars[i].characteristic.handle_value;
                    nus_c_evt.handles.nus_tx_cccd_handle = p_chars[i].cccd_handle;
                    break;

                default:
                    break;
            }
        }
        if (p_ble_nus_c->evt_handler != NULL)
        {
            nus_c_evt.conn_handle = p_evt->conn_handle;
            nus_c_evt.evt_type    = BLE_NUS_C_EVT_DISCOVERY_COMPLETE;
            p_ble_nus_c->evt_handler(p_ble_nus_c, &nus_c_evt);
        }
    }
}
```

对于ble_app_uart_c 工程，蓝牙主机（也即nRF52 DK）可以发现连接的从机设备公开的NUS 服务。服务发现过程完成后（也即触发事件BLE_DB_DISCOVERY_COMPLETE），会执行函数db_disc_handler。然后在函数函数ble_nus_c_on_db_disc_evt 中，触发事件BLE_NUS_C_EVT_DISCOVERY_COMPLETE，并调用由NUS Client 初始化函数nus_c_init 注册的事件处理函数ble_nus_c_evt_handler，执行后续的响应动作，该函数的实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
BLE_NUS_C_DEF(m_ble_nus_c);                                             /**< BLE Nordic UART Service (NUS) client instance. */

/**@brief Function for initializing the Nordic UART Service (NUS) client. */
static void nus_c_init(void)
{
    ret_code_t       err_code;
    ble_nus_c_init_t init;

    init.evt_handler   = ble_nus_c_evt_handler;
    init.error_handler = nus_error_handler;
    init.p_gatt_queue  = &m_ble_gatt_queue;

    err_code = ble_nus_c_init(&m_ble_nus_c, &init);
    APP_ERROR_CHECK(err_code);
}

/**@brief Callback handling Nordic UART Service (NUS) client events.
 * @details This function is called to notify the application of NUS client events.
 * @param[in]   p_ble_nus_c   NUS client handle. This identifies the NUS client.
 * @param[in]   p_ble_nus_evt Pointer to the NUS client event. */
static void ble_nus_c_evt_handler(ble_nus_c_t * p_ble_nus_c, ble_nus_c_evt_t const * p_ble_nus_evt)
{
    ret_code_t err_code;

    switch (p_ble_nus_evt->evt_type)
    {
        case BLE_NUS_C_EVT_DISCOVERY_COMPLETE:
            NRF_LOG_INFO("Discovery complete.");
            err_code = ble_nus_c_handles_assign(p_ble_nus_c, p_ble_nus_evt->conn_handle, &p_ble_nus_evt->handles);
            APP_ERROR_CHECK(err_code);

            err_code = ble_nus_c_tx_notif_enable(p_ble_nus_c);
            APP_ERROR_CHECK(err_code);
            NRF_LOG_INFO("Connected to device with Nordic UART Service.");
            break;

        case BLE_NUS_C_EVT_NUS_TX_EVT:
            ble_nus_chars_received_uart_print(p_ble_nus_evt->p_data, p_ble_nus_evt->data_len);
            break;

        case BLE_NUS_C_EVT_DISCONNECTED:
            NRF_LOG_INFO("Disconnected.");
            scan_start();
            break;
    }
}


```

触发事件BLE_NUS_C_EVT_DISCOVERY_COMPLETE 后，调用NUS Client 注册的事件处理函数ble_nus_c_evt_handler，执行对应的事件分支。值得一提的是，在事件分支BLE_NUS_C_EVT_DISCOVERY_COMPLETE 中会调用函数ble_nus_c_tx_notif_enable，允许GATT Server 以Notification 的形式主动向GATT Client 传输数据。如果这里没有配置为允许GATT Server 通知功能，GATT Client 就无法及时获取GATT Server 最新的数据，只能在需要时主动向GATT Server 请求服务数据。

到这里，蓝牙主机（也即GATT Client）已经发现了GATT Server 公开的NUS 服务，且允许GATT Server 以Notification 的形式主动向GATT Client 传输数据。当GATT Client 需要向GATT Server 发送数据时，执行GATTC Write Request 即可。当GATT Client 接收到来自GATT Server 的通知数据时，GATT Client 协议栈会触发事件BLE_GATTC_EVT_HVX，并执行对应的事件处理函数ble_nus_c_on_ble_evt，该过程的实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_services\ble_nus_c\ble_nus_c.h
/**@brief   Macro for defining a ble_nus_c instance. */
#define BLE_NUS_C_DEF(_name)                                                                        \
static ble_nus_c_t _name;                                                                           \
NRF_SDH_BLE_OBSERVER(_name ## _obs,                                                                 \
                     BLE_NUS_C_BLE_OBSERVER_PRIO,                                                   \
                     ble_nus_c_on_ble_evt, &_name)


// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_services\ble_nus_c\ble_nus_c.c
void ble_nus_c_on_ble_evt(ble_evt_t const * p_ble_evt, void * p_context)
{
    ble_nus_c_t * p_ble_nus_c = (ble_nus_c_t *)p_context;

    if ((p_ble_nus_c == NULL) || (p_ble_evt == NULL))
    {
        return;
    }

    if ( (p_ble_nus_c->conn_handle == BLE_CONN_HANDLE_INVALID)
       ||(p_ble_nus_c->conn_handle != p_ble_evt->evt.gap_evt.conn_handle)
       )
    {
        return;
    }

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GATTC_EVT_HVX:
            on_hvx(p_ble_nus_c, p_ble_evt);
            break;

        case BLE_GAP_EVT_DISCONNECTED:
            if (p_ble_evt->evt.gap_evt.conn_handle == p_ble_nus_c->conn_handle
                    && p_ble_nus_c->evt_handler != NULL)
            {
                ble_nus_c_evt_t nus_c_evt;

                nus_c_evt.evt_type = BLE_NUS_C_EVT_DISCONNECTED;

                p_ble_nus_c->conn_handle = BLE_CONN_HANDLE_INVALID;
                p_ble_nus_c->evt_handler(p_ble_nus_c, &nus_c_evt);
            }
            break;

        default:
            // No implementation needed.
            break;
    }
}

/**@brief     Function for handling Handle Value Notification received from the SoftDevice.          
 * @param[in] p_ble_nus_c Pointer to the NUS Client structure.
 * @param[in] p_ble_evt   Pointer to the BLE event received. */
static void on_hvx(ble_nus_c_t * p_ble_nus_c, ble_evt_t const * p_ble_evt)
{
    // HVX can only occur from client sending.
    if (   (p_ble_nus_c->handles.nus_tx_handle != BLE_GATT_HANDLE_INVALID)
        && (p_ble_evt->evt.gattc_evt.params.hvx.handle == p_ble_nus_c->handles.nus_tx_handle)
        && (p_ble_nus_c->evt_handler != NULL))
    {
        ble_nus_c_evt_t ble_nus_c_evt;

        ble_nus_c_evt.evt_type = BLE_NUS_C_EVT_NUS_TX_EVT;
        ble_nus_c_evt.p_data   = (uint8_t *)p_ble_evt->evt.gattc_evt.params.hvx.data;
        ble_nus_c_evt.data_len = p_ble_evt->evt.gattc_evt.params.hvx.len;

        p_ble_nus_c->evt_handler(p_ble_nus_c, &ble_nus_c_evt);
        NRF_LOG_DEBUG("Client sending data.");
    }
}
```

GATT Client 协议栈触发事件BLE_GATTC_EVT_HVX 后，会调用函数on_hvx 来处理接收到的通知数据，该函数会触发事件BLE_NUS_C_EVT_NUS_TX_EVT，并调用NUS Client 初始化过程注册的事件处理函数ble_nus_c_evt_handler，该函数选择执行事件BLE_NUS_C_EVT_NUS_TX_EVT 分支，也即调用函数ble_nus_chars_received_uart_print，该函数实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
#define ECHOBACK_BLE_UART_DATA  0                                       /**< Echo the UART data that is received over the Nordic UART Service (NUS) back to the sender. */

/**@brief Function for handling characters received by the Nordic UART Service (NUS). */
static void ble_nus_chars_received_uart_print(uint8_t * p_data, uint16_t data_len)
{
    ret_code_t ret_val;
	......
    for (uint32_t i = 0; i < data_len; i++)
    {
        do
        {
            ret_val = app_uart_put(p_data[i]);
            ......
        } while (ret_val == NRF_ERROR_BUSY);
    }
    if (p_data[data_len-1] == '\r')
    {
        while (app_uart_put('\n') == NRF_ERROR_BUSY);
    }
    if (ECHOBACK_BLE_UART_DATA)
    {
        // Send data back to the peripheral.
        do
        {
            ret_val = ble_nus_c_string_send(&m_ble_nus_c, p_data, data_len);
            ......
        } while (ret_val == NRF_ERROR_BUSY);
    }
}


// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_services\ble_nus_c\ble_nus_c.c
uint32_t ble_nus_c_string_send(ble_nus_c_t * p_ble_nus_c, uint8_t * p_string, uint16_t length)
{
    VERIFY_PARAM_NOT_NULL(p_ble_nus_c);

    nrf_ble_gq_req_t write_req;

    memset(&write_req, 0, sizeof(nrf_ble_gq_req_t));

    if (length > BLE_NUS_MAX_DATA_LEN)
    {
        NRF_LOG_WARNING("Content too long.");
        return NRF_ERROR_INVALID_PARAM;
    }
    if (p_ble_nus_c->conn_handle == BLE_CONN_HANDLE_INVALID)
    {
        NRF_LOG_WARNING("Connection handle invalid.");
        return NRF_ERROR_INVALID_STATE;
    }

    write_req.type                        = NRF_BLE_GQ_REQ_GATTC_WRITE;
    ......

    return nrf_ble_gq_item_add(p_ble_nus_c->p_gatt_queue, &write_req, p_ble_nus_c->conn_handle);
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gattc.h
/**@brief Perform a Write (Characteristic Value or Descriptor, with or without response, signed or not, long or reliable) procedure.
 * @event{@ref BLE_GATTC_EVT_WRITE_CMD_TX_COMPLETE, Write without response transmission complete.}
 * @event{@ref BLE_GATTC_EVT_WRITE_RSP, Write response received from the peer.} */
SVCALL(SD_BLE_GATTC_WRITE, uint32_t, sd_ble_gattc_write(uint16_t conn_handle, ble_gattc_write_params_t const *p_write_params));
```

函数ble_nus_chars_received_uart_print 实际上就是把GATT Client 协议栈接收到的通知数据输出到串口外设，PC 就可以通过UART 读取nRF52 DK（GATT Client） 接收到的来自目标从机设备（GATT Server）的通知数据。值得一提的是，宏定义ECHOBACK_BLE_UART_DATA 默认配置为将接收到的通知数据回传给GATT Server，我们并不需要该功能，因此将该宏配置为0。

如果GATT Client 需要向GATT Server 发送数据，可以通过调用函数ble_nus_c_string_send 实现，该函数会向GATT Server 发送特征值写入请求，也是放入GATT 队列（也即m_ble_gatt_queue）管理的，最后在队列处理函数queue_process 中执行分支NRF_BLE_GQ_REQ_GATTC_WRITE，通过调用GATT Client 协议栈接口函数sd_ble_gattc_write 完成向GATT Server 发送数据的过程。

到这里，蓝牙主机与从机设备之间已经建立连接，并可以借助NUS 服务相互传输数据。然而，我们的扫码连接功能开发工作并未结束，前面还有一个悬置的问题尚未解决，蓝牙主机如何获得目标设备的MAC 地址呢？这就要靠nRF52 DK 通过UART 从PC 获得了。

## 2.4 UART(串口外设初始化和访问过程)
PC 与nRF52 DK 之间要想通过UART 串口传输数据，需要先完成UART 外设的初始化，该过程的实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
#define UART_TX_BUF_SIZE        256                                     /**< UART TX buffer size. */
#define UART_RX_BUF_SIZE        256                                     /**< UART RX buffer size. */

/**@brief Function for initializing the UART. */
static void uart_init(void)
{
    ret_code_t err_code;

    app_uart_comm_params_t const comm_params =
    {
        .rx_pin_no    = RX_PIN_NUMBER,
        .tx_pin_no    = TX_PIN_NUMBER,
        .rts_pin_no   = RTS_PIN_NUMBER,
        .cts_pin_no   = CTS_PIN_NUMBER,
        .flow_control = APP_UART_FLOW_CONTROL_DISABLED,
        .use_parity   = false,
        .baud_rate    = UART_BAUDRATE_BAUDRATE_Baud115200
    };

    APP_UART_FIFO_INIT(&comm_params,
                       UART_RX_BUF_SIZE,
                       UART_TX_BUF_SIZE,
                       uart_event_handle,
                       APP_IRQ_PRIORITY_LOWEST,
                       err_code);

    APP_ERROR_CHECK(err_code);
}


/**@brief   Function for handling app_uart events.
 * @details This function receives a single character from the app_uart module and appends it to
 *          a string. The string is sent over BLE when the last character received is a
 *          'new line' '\n' (hex 0x0A) or if the string reaches the maximum data length. */
void uart_event_handle(app_uart_evt_t * p_event)
{
    static uint8_t data_array[BLE_NUS_MAX_DATA_LEN];
    static uint16_t index = 0;
    uint32_t ret_val;

    switch (p_event->evt_type)
    {
        /**@snippet [Handling data from UART] */
        case APP_UART_DATA_READY:
            UNUSED_VARIABLE(app_uart_get(&data_array[index]));
            index++;

            if ((data_array[index - 1] == '\n') ||
                (data_array[index - 1] == '\r') ||
                (index >= (m_ble_nus_max_data_len)))
            {
                NRF_LOG_DEBUG("Ready to send data over BLE NUS");
                NRF_LOG_HEXDUMP_DEBUG(data_array, index);

                do
                {
                    ret_val = ble_nus_c_string_send(&m_ble_nus_c, data_array, index);
                    if ( (ret_val != NRF_ERROR_INVALID_STATE) && (ret_val != NRF_ERROR_RESOURCES) )
                    {
                        APP_ERROR_CHECK(ret_val);
                    }
                } while (ret_val == NRF_ERROR_RESOURCES);

                index = 0;
            }
            break;

        /**@snippet [Handling data from UART] */
        case APP_UART_COMMUNICATION_ERROR:
            NRF_LOG_ERROR("Communication error occurred while handling UART.");
            APP_ERROR_HANDLER(p_event->data.error_communication);
            break;

        case APP_UART_FIFO_ERROR:
            NRF_LOG_ERROR("Error occurred in FIFO module used by UART.");
            APP_ERROR_HANDLER(p_event->data.error_code);
            break;

        default:
            break;
    }
}

static uint16_t m_ble_nus_max_data_len = BLE_GATT_ATT_MTU_DEFAULT - OPCODE_LENGTH - HANDLE_LENGTH; /**< Maximum length of data (in bytes) that can be transmitted to the peer by the Nordic UART service module. */

// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gatt.h
/** @brief Default ATT MTU, in bytes. */
#define BLE_GATT_ATT_MTU_DEFAULT          23

// .\nRF5_SDK_17.0.2_d674dde\components\ble\ble_services\ble_nus_c\ble_nus_c.h
#define OPCODE_LENGTH 1
#define HANDLE_LENGTH 2
```

函数uart_init 为UART 配置GPIO 引脚、波特率（115200 baud）等通信参数，并向UART 模块注册了事件处理函数uart_event_handle，待UART 接收数据完毕后，通知应用层处理UART 接收到的数据。为UART 分配FIFO 缓存空间，并初始化UART 外设驱动的代码就不展开介绍了，想进一步了解UART 通讯原理，可参考博文：[USART + DMA](https://blog.csdn.net/m0_37621078/article/details/100164277)。

前面介绍了GATT Client 接收到来自GATT Server 的通知数据后，执行函数ble_nus_chars_received_uart_print 将通知数据输出到UART 外设，也即nRF52 DK 将接收到的通知数据通过UART 发送给PC。当GATT Client 通过UART 接收完来自PC 的数据，则会触发事件APP_UART_DATA_READY，执行UART 事件处理函数uart_event_handle，处理从UART 接收到的数据。

原工程ble_app_uart_c 处理从UART 接收到数据的逻辑也很简单，nRF52 DK（也即GATT Client）先判断接收到的字符串是否完整（也即是否包含结束符‘\r’ 或‘\n' ）或者是否超出NUS 服务支持的最大数据长度（m_ble_nus_max_data_len 默认值为20，若发生MTU 交换，该值也会同步更新），如果符合上述任一条件，则调用函数ble_nus_c_string_send 将UART 接收到的数据通过BLE NUS 发送给连接的对端设备（也即GATT Server）。

我们把目标设备地址从PC 经UART 串口发送给蓝牙主机nRF52 DK 后，蓝牙主机也需要在函数uart_event_handle 中处理接收到的目标设备地址，并将其设置到扫描过滤器中。

Windows PC 通过摄像头或者扫码枪获得的MAC 地址一般是MSB（也即大端字节序或者最高有效位）字符串格式，Nordic softdevice 处理的是LSB（也即小端字节序或最低有效位）十六进制格式。这里有两个问题需要解决：一个是将PC 通过UART 发来的设备地址字符串从MSB 转换为LSB（比如将“E7C21EC0E768” 转换为“68E7C01EC2E7”）；另一个是将设备地址从十二位字符串转换为六个字节（比如将“68E7C01EC2E7” 转换为{0x68, 0xE7, 0xC0, 0x1E, 0xC2, 0xE7}）。

蓝牙主机除了要实现对目标设备地址字符串的正确处理，还需要能从通信数据中识别哪段字符是目标设备地址。一个常用的方法是，我们将目标设备地址封装为一条指令，蓝牙主机接收到一个字符串后，可通过前缀或后缀判断该字符串是不是一条指令，并根据判断结果执行预设的响应动作，可以根据需要以前后缀区分并设置多条指令。本文我们将目标设备地址封装为“conn:E7C21EC0E768” 的形式，通过前缀”conn:“ 或”CONN:“ 辨识出其后包含的是目标设备的MAC 地址，然后对其进行处理，实现代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief String convert to HEX.  */
static uint16_t StringToHex(char * str, uint8_t * out)
{
    char *p = str;
    uint8_t high = 0, low = 0;
    uint16_t tmplen = strlen(p), cnt = 0;

	// String convert to octet array
    while(cnt < (tmplen / 2))
    {
        high = ((*p > '9') && ((*p <= 'F') || (*p <= 'f'))) ? *p - 48 - 7 : *p - 48;
        p ++;
        low = ((*p > '9') && ((*p <= 'F') || (*p <= 'f'))) ? *p - 48 - 7 : *p - 48;
        out[cnt] = ((high & 0x0f) << 4 | (low & 0x0f));
        p ++;
        cnt ++;
    }
    if(tmplen % 2 != 0) out[cnt] = ((*p > '9') && ((*p <= 'F') || (*p <= 'f'))) ? *p - 48 - 7 : *p - 48;

    return tmplen / 2 + tmplen % 2;
}

/**@brief Process commands from UART. */
static uint8_t uart_cmd_process(uint8_t * p_data, uint16_t * p_index)
{
    uint8_t i, temp_data[2*BLE_GAP_ADDR_LEN + 1];

    p_data[*p_index] = '\0';

	// Handle commands that connect to a specified target device.
    if(strlen(p_data) >= 17 && (strncmp(p_data, "CONN:", 5) == 0 || strncmp(p_data, "conn:", 5) == 0))
    {
        // MSB(Most Significant Bit) convert to LSB(Least Significant Bit)
        for (i = 0; i < 2*BLE_GAP_ADDR_LEN; i++)
        {
            temp_data[i] = p_data[5 + 2*BLE_GAP_ADDR_LEN - 2 - i];
            i++;
            temp_data[i] = p_data[5 + 2*BLE_GAP_ADDR_LEN - i];
        }

        temp_data[i] = '\0';

        if(StringToHex((char *)temp_data, m_ble_addr) == BLE_GAP_ADDR_LEN)
        {
            *p_index = 0;
            scan_init(m_ble_addr);
            scan_start();
        }
    }

    return *p_index;
}

/**@brief   Function for handling app_uart events. */
void uart_event_handle(app_uart_evt_t * p_event)
{
    ......
    switch (p_event->evt_type)
    {
        /**@snippet [Handling data from UART] */
        case APP_UART_DATA_READY:
            UNUSED_VARIABLE(app_uart_get(&data_array[index]));
            index++;

            if ((data_array[index - 1] == '\n') ||
                (data_array[index - 1] == '\r') ||
                (index >= (m_ble_nus_max_data_len)))
            {
                // Process commands from UART.
                if(uart_cmd_process(data_array, &index) == 0)
                    break;
                
                NRF_LOG_DEBUG("Ready to send data over BLE NUS");
                NRF_LOG_HEXDUMP_DEBUG(data_array, index);

                do
                {
                    ret_val = ble_nus_c_string_send(&m_ble_nus_c, data_array, index);
                    ......
                } while (ret_val == NRF_ERROR_RESOURCES);

                index = 0;
            }
            break;
        ......
    }
}
```

蓝牙主机从UART 接收完一段数据后，触发事件APP_UART_DATA_READY，并调用串口事件处理函数uart_event_handle 处理从UART 接收到的数据。原工程ble_app_uart_c 判断接收到的字符串包含结束符（'\n' 或'\r'）或超出SDU 最大长度（m_ble_nus_max_data_len），直接调用函数ble_nus_c_string_send 将该字符串经NUS 服务发送给BLE 连接的对端设备（也即GATT Server），现在我们需要先对字符串进行处理，因此在接收到字符串后调用函数uart_cmd_process 处理可能包含的指令。

我们编写的uart_cmd_process 函数主要用来处理PC 经UART 发送给nRF52 DK 的指令，如果判断不是指令则不对其处理。首先，我们判断字符串中是否包含前缀”conn:“ 或”CONN:“，如果前缀匹配则冒号后面是目标设备的地址信息，我们先将目标设备地址从MSB 转换为LSB，然后调用函数StringToHex 将12位字符串转换为6个字节数组。最后，处理后的目标设备地址（m_ble_addr）借助函数scan_init 参数设置到扫描过滤器中，再以新的扫描过滤条件重新开始扫描过程。

到这里，我们要实现的扫码连接功能已经实现了，PC 通过摄像头或扫码枪获取目标设备地址的过程就省去了，我们编译工程无报错，接下来需要将代码烧录到nRF52 DK 中验证扫码连接功能是否可以正常工作。

# 三、扫码连接功能验证
## 3.1 扫码连接功能验证
我们将编译后的工程代码通过J-Link 烧录到nRF52 DK 中，开发板将会扫描周围可发现的蓝牙设备。由于我们设置了设备地址过滤条件，且设备地址初始值为0，开发板不会连接到任何设备。当我们通过UART 向nRF52 DK 发送包含目标设备地址的指令”conn:deviceaddress“ (比如"conn:E7C21EC0E768")，并以回车换行符结束（也即勾选”发送新行“），开发板将扫描MAC地址为E7C21EC0E768 的设备，当扫描到目标设备后自动向其发起连接。

我们可以借助J-Link RTT Viewer 来查看开发板输出的log 信息，工程中已经通过函数log_init 完成了log 模块的初始化，log 输出等级默认为Info。J-Link RTT Viewer 输出的log 信息和putty 串口交互信息如下：

![扫码连接功能输出日志与串口命令](https://img-blog.csdnimg.cn/20201031014409276.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

我们从J-Link RTT Viewer 输出的log 信息可知，PC 通过UART 向开发板发送连接到目标设备指令”conn:E7C21EC0E768“ 后，开发板成功连接到目标设备，完成ATT MTU 交换和服务发现过程，发现了目标设备公开的Nordic UART Service，连接双方就可以借助NUS 服务相互传输数据了。

putty 并没有输出成功连接目标设备信息和服务发现信息，PC 端想获知nRF52 DK 的状态，可以通过printf 函数将需要通知PC 端的信息写入到UART 模块。比如，我们分别在成功连接目标设备时、完成服务发现时、双方连接断开时，这三种情况下通知PC 端相关的状态信息，可参考NRF_LOG_INFO 语句。值得一提的是，设备地址默认以LSB 格式输出，如果要在windows PC 上看到正确的MAC 地址信息，在printf 函数中需要将其转换为MSB 格式输出。

![串口新增状态通知信息](https://img-blog.csdnimg.cn/20201031021038489.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

putty 已经输出了我们通过函数printf 新增的状态通知信息，中间部分是GATT Client 向GATT Server 请求数据的过程，比如GATT Client 向GATT Server 发送”sw“ 查询软件版本，GATT Server 通知GATT Client 自己的软件版本是”0.27“。上述验证结果说明连接双方通讯正常，我们实现的扫码连接功能没有明显Bug。

## 3.2 新增获取RSSI 功能
如果我们想在上述工程的基础上增加点功能或者UART 指令，比如PC 端通过UART 获取nRF52 DK 与目标设备连接的信号强度RSSI (Received Signal Strength Indication)，该怎么实现呢？

蓝牙主机nRF52 DK 获取双方连接的信号强度RSSI 也需要调用协议栈softdevice 的接口函数，该调用哪个接口函数、调用流程是怎样的呢？我们打开nRF5 SDK 文档，搜索关键字"rssi"，可以获得如下的示例流程（[GAP RSSI get sample](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/index.html)）：

![BLE GAP RSSI GET SAMPLE](https://img-blog.csdnimg.cn/20201031112739309.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

上图已经告诉我们，可通过调用softdevice 接口函数sd_ble_gap_rssi_get 获得RSSI 值，在此之前需要先执行sd_ble_gap_rssi_start 函数让协议栈开始记录RSSI 信息。记录RSSI 信息需要在双方连接建立成功后才有意义，因此我们在协议栈softdevice 触发事件BLE_GAP_EVT_CONNECTED 后调用函数sd_ble_gap_rssi_start。前面介绍过，协议栈触发连接成功事件后，会到注册的事件处理函数ble_evt_handler 中选择执行事件BLE_GAP_EVT_CONNECTED 分支，我们在该分支下新增函数sd_ble_gap_rssi_start 的调用代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief Function for handling BLE events. */
static void ble_evt_handler(ble_evt_t const * p_ble_evt, void * p_context)
{
    ret_code_t            err_code;
    ble_gap_evt_t const * p_gap_evt = &p_ble_evt->evt.gap_evt;

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_CONNECTED:
            ......
            // start discovery of services. The NUS Client waits for a discovery result
            err_code = ble_db_discovery_start(&m_db_disc, p_ble_evt->evt.gap_evt.conn_handle);
            APP_ERROR_CHECK(err_code);

            // Start reporting the received signal strength to the application.
            err_code = sd_ble_gap_rssi_start(p_ble_evt->evt.gap_evt.conn_handle, 0x03, 0x00);
            APP_ERROR_CHECK(err_code);

            break;
        ......
    }
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gap.h
/**@brief Start reporting the received signal strength to the application.
 * @event{@ref BLE_GAP_EVT_RSSI_CHANGED, New RSSI data available. How often the event is generated is dependent on the settings
 *                                       of the <code>threshold_dbm</code> and <code>skip_count</code> input parameters.} */
SVCALL(SD_BLE_GAP_RSSI_START, uint32_t, sd_ble_gap_rssi_start(uint16_t conn_handle, uint8_t threshold_dbm, uint8_t skip_count));
```

协议栈执行函数sd_ble_gap_rssi_start 后，如果RSSI 变化范围超过设定阈值（比如上文RSSI 变更阈值设置为3dBm）则会触发事件BLE_GAP_EVT_RSSI_CHANGED，该事件的处理函数是哪个呢？考虑到RSSI 属于BLE 协议栈的基础属性，我们猜测并查看ble_gap_evt_t 是否包含该事件：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gap.h
/**@brief GAP Event IDs.
 * IDs that uniquely identify an event coming from the stack to the application. */
enum BLE_GAP_EVTS
{
  BLE_GAP_EVT_CONNECTED                   = BLE_GAP_EVT_BASE,       /**< Connected to peer.                              \n See @ref ble_gap_evt_connected_t             */
  BLE_GAP_EVT_DISCONNECTED                = BLE_GAP_EVT_BASE + 1,   /**< Disconnected from peer.                         \n See @ref ble_gap_evt_disconnected_t.         */
  BLE_GAP_EVT_CONN_PARAM_UPDATE           = BLE_GAP_EVT_BASE + 2,   /**< Connection Parameters updated.                  \n See @ref ble_gap_evt_conn_param_update_t.    */
  ......
  BLE_GAP_EVT_RSSI_CHANGED                = BLE_GAP_EVT_BASE + 12,  /**< RSSI report.                                    \n See @ref ble_gap_evt_rssi_changed_t.         */
  ......
};
```

事件类型BLE_GAP_EVTS 信息证实了我们的猜测，因此我们可以在BLE 事件处理函数ble_evt_handler 中新增事件BLE_GAP_EVT_RSSI_CHANGED 响应分支，并在该分支下调用函数sd_ble_gap_rssi_get 获得当前RSSI 信息。为便于保存RSSI 信息，我们新增变量m_ble_rssi，获取RSSI 信息的代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief BLE Received Signal Strength Indication. */
static ble_gap_evt_rssi_changed_t m_ble_rssi;

/**@brief Function for handling BLE events. */
static void ble_evt_handler(ble_evt_t const * p_ble_evt, void * p_context)
{
    ret_code_t            err_code;
    ble_gap_evt_t const * p_gap_evt = &p_ble_evt->evt.gap_evt;

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_CONNECTED:
            ......
            // Start reporting the received signal strength to the application.
            err_code = sd_ble_gap_rssi_start(p_ble_evt->evt.gap_evt.conn_handle, 0x03, 0x00);
            APP_ERROR_CHECK(err_code);

            break;

        case BLE_GAP_EVT_RSSI_CHANGED:
            // Get the received signal strength for the last connection event.
            err_code = sd_ble_gap_rssi_get(p_ble_evt->evt.gap_evt.conn_handle, &m_ble_rssi.rssi, &m_ble_rssi.ch_index);
            APP_ERROR_CHECK(err_code);

            NRF_LOG_INFO("RSSI: %d dBm, Data Channel Index: %d.", m_ble_rssi.rssi, m_ble_rssi.ch_index);

            break;
        ......
    }
}


// .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\headers\ble_gap.h
/**@brief Get the received signal strength for the last connection event. */
SVCALL(SD_BLE_GAP_RSSI_GET, uint32_t, sd_ble_gap_rssi_get(uint16_t conn_handle, int8_t *p_rssi, uint8_t *p_ch_index));
```

到这里，我们已经将获得的当前RSSI 信息保存在全局变量m_ble_rssi 中，PC 端要想从nRF52 DK 获得连接的信号强度，只需要从UART 发送相应指令即可。我们假设PC 向nRF52 DK 发送字符串”RSSI“ 或”rssi“，nRF52 DK 会向UART 发送当前RSSI 信息，在函数uart_cmd_process 中新增处理该指令的代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_central\ble_app_uart_c\main.c
/**@brief Process commands from UART.  */
static uint8_t uart_cmd_process(uint8_t * p_data, uint16_t * p_index)
{
    uint8_t i, temp_data[2*BLE_GAP_ADDR_LEN + 1];

    p_data[*p_index] = '\0';

    // Handle commands that connect to a specified target device.
    ......
    
    // Handle commands to obtain RSSI information.
    if(strlen(p_data) >= 4 && (strncmp(p_data, "RSSI", 4) == 0 || strncmp(p_data, "rssi", 4) == 0))
    {
        *p_index = 0;
        printf("RSSI: %d dBm, Data Channel Index: %d.\r\n", m_ble_rssi.rssi, m_ble_rssi.ch_index);
    }
    ......
    return *p_index;
}
```

 PC 端通过UART 命令获取nRF52 DK 与目标设备连接的实时信号强度RSSI 的功能就实现完成了，编译工程无报错，通过J-Link 将编译后的代码烧录到开发板中，依然使用J-Link RTT Viewer 查看nRF52 DK 输出的Log 信息，使用putty 工具通过UART 与nRF52 DK 交互命令与数据，结果如下：

![新增获取RSSI 信息的串口指令](https://img-blog.csdnimg.cn/2020103112550778.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)




# 更多文章：

 - 《[Bluetooth 技术（一）--- 协议栈设计与演进(Core_v5.2)](https://blog.csdn.net/m0_37621078/article/details/106995704)》
 - 《[BLE 技术（二）--- 协议栈架构与物理层设计 (Core_v5.2)](https://blog.csdn.net/m0_37621078/article/details/107411324)》
 - 《[BLE 技术（三）--- 链路层七种状态与空口报文设计(Core_v5.2)](https://blog.csdn.net/m0_37621078/article/details/107697019)》
 - 《[BLE 技术（四）--- 链路层广播通信与连接通信 (Core_v5.2)](https://blog.csdn.net/m0_37621078/article/details/107724799)》
 - 《[BLE 技术（五）--- Generic Access Profile + Security Manager(Core_v5.2)](https://blog.csdn.net/m0_37621078/article/details/107850523)》
 - 《[BLE 技术（六）--- GATT Profile + ATT protocol + L2CAP(Core_v5.2)](https://blog.csdn.net/m0_37621078/article/details/108391261)》
 - 《[Bluetooth Core Specification_v5.2](https://www.bluetooth.com/specifications/bluetooth-core-specification/)》
 - 《[Nordic nRF5 SDK documentation](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/index.html)》