# 如何为BLE 设备添加OTA DFU 空中升级服务（下）？
@[TOC]

> 前篇博文详细介绍了[BLE 设备实现OTA DFU 功能](https://blog.csdn.net/m0_37621078/article/details/115541552)的工作原理，也借助Nordic SDK 提供的示例工程展示了执行Buttonless BLE DFU 的过程。重点是，我们如何为自己开发的BLE 工程添加BLE DFU Service 呢？

# 一、如何为Nordic 工程添加Service？
要想为Nordic SDK 工程添加服务或者应用逻辑，需要先了解SDK 的代码组织结构，我们选用Nordic 芯片通常用来开发BLE 芯片，都是带SoftDeice 协议栈的，带BLE Protocol Stack 的软件架构如下：
![SoC application with the SoftDevice](https://img-blog.csdnimg.cn/20210417192609904.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
从下到上，大致可以分为三层：

 - **nRF5x Drivers**：对于ARM 架构芯片须符合CMSIS(Cortex Microcontroller Software Interface Standard)，用于驱动芯片硬件外设模块，比如UART、SPI、TWI (IIC)、SDIO 等；
 - **SoftDevice / Libraries**：SoftDevice 是BLE 协议栈的实现，Nordic 以hex 文件形式提供，对应用层提供了相应的Protocol API。Libraries 是为方便管理共享硬件资源开发的一个个资源管理模块，对上层应用提供相应nRF API，比如 Atomic、FIFO / Queue、SHA256 / CRC32、Crypto  / ECC、App_timer 等；
 - **BLE Services**：根据业务需求开发的一个个应用服务BLE Services / Profiles，nRF SDK 也提供了很多常见的BLE Services，比如ble_dfu、ble_nus、ble_battery、ble_hrs、ble_proximity 等。

前篇博文介绍[Nordic Memory layout](https://blog.csdn.net/m0_37621078/article/details/107411324?spm=1001.2014.3001.5501#t2) 时谈到，Nordic SoftDevice 和 Application 是分别存储在两个flash 分区的，二者代码区相互独立，可以分别独立进行升级。SoftDevice 和 Application 运行时使用的RAM 地址空间也是相互独立的（Bootloader 和Application 不会同时运行，因此复用RAM 地址空间），SoftDevice 运行时使用的RAM start address 和RAM size 需要根据BLE Services 数量和Attribute table 大小进行调整。
![Nordic Memory resource map](https://img-blog.csdnimg.cn/20210419154651933.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
Application 和SoftDevice 分别存储运行在不同的Flash 和RAM 地址空间，二者之间如何通讯呢？SoftDevice 对上层应用提供了SoftDevice API，上层应用调用SoftDevice API 实际上是触发SV Call (Supervisor Call)  interrupt，每个API 都有一个SVC numbers，SoftDevice 根据SVC numbers 执行相应的事件处理，待该事件处理完毕后，SoftDevice 会触发SWI (Software Interrupt)，通知Application 请求事件已处理完毕，可以继续进行后续的数据处理或业务逻辑了。

# 二、如何为工程添加BLE DFU Service？
 我们选择一个比较常用的工程ble_app_uart 为例，在该示例工程中添加DFU 服务，为了方便判断DFU 前后版本对比，可以在工程ble_app_uart 中添加读取当前软件版本的命令。

首先我们查看BLE DFU 服务的相关介绍：[Buttonless Secure DFU Service](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/service_dfu.html)，了解到其主要分为Buttonless DFU without bonds 和Buttonless DFU with bonds 两种情况，后者需要配对绑定过程，因此需要Peer Manager Libraries。二者还需要Power Management library，用于控制BLE 系统重置进入DFU mode 的时间，下面分别介绍如何向工程ble_app_uart 中添加Buttonless DFU without bonds 和Buttonless DFU with bonds 服务。

## 2.1 如何为工程添加Buttonless DFU without bonds service？
首先，往工程ble_app_uart 中添加DFU 需要的源文件和头文件路径如下（可以复制工程ble_app_uart 为ble_app_uart_dfu，并在工程ble_app_uart_dfu 基础上开发）：
![Segger 添加ble_dfu service](https://img-blog.csdnimg.cn/20210419171149448.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
在services_init 函数中新增初始化DFU 服务、并注册相应的事件处理函数ble_dfu_evt_handler，再在sdk_config 中配置使能BLE_DFU 服务如下（从工程ble_app_buttonless_dfu 复制而来）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu\main.c
// Add DFU service
#include "ble_dfu.h"

static void advertising_config_get(ble_adv_modes_config_t * p_config)
{
    memset(p_config, 0, sizeof(ble_adv_modes_config_t));

    p_config->ble_adv_fast_enabled  = true;
    p_config->ble_adv_fast_interval = APP_ADV_INTERVAL;
    p_config->ble_adv_fast_timeout  = APP_ADV_DURATION;
}

static void disconnect(uint16_t conn_handle, void * p_context)
{
    UNUSED_PARAMETER(p_context);

    ret_code_t err_code = sd_ble_gap_disconnect(conn_handle, BLE_HCI_REMOTE_USER_TERMINATED_CONNECTION);
    if (err_code != NRF_SUCCESS)
    {
        NRF_LOG_WARNING("Failed to disconnect connection. Connection handle: %d Error: %d", conn_handle, err_code);
    }
    else
    {
        NRF_LOG_DEBUG("Disconnected connection handle %d", conn_handle);
    }
}

// YOUR_JOB: Update this code if you want to do anything given a DFU event (optional).
/**@brief Function for handling dfu events from the Buttonless Secure DFU service
 *
 * @param[in]   event   Event from the Buttonless Secure DFU service.
 */
static void ble_dfu_evt_handler(ble_dfu_buttonless_evt_type_t event)
{
    switch (event)
    {
        case BLE_DFU_EVT_BOOTLOADER_ENTER_PREPARE:
        {
            NRF_LOG_INFO("Device is preparing to enter bootloader mode.");

            // Prevent device from advertising on disconnect.
            ble_adv_modes_config_t config;
            advertising_config_get(&config);
            config.ble_adv_on_disconnect_disabled = true;
            ble_advertising_modes_config_set(&m_advertising, &config);

            // Disconnect all other bonded devices that currently are connected.
            // This is required to receive a service changed indication
            // on bootup after a successful (or aborted) Device Firmware Update.
            uint32_t conn_count = ble_conn_state_for_each_connected(disconnect, NULL);
            NRF_LOG_INFO("Disconnected %d links.", conn_count);
            break;
        }

        case BLE_DFU_EVT_BOOTLOADER_ENTER:
            // YOUR_JOB: Write app-specific unwritten data to FLASH, control finalization of this
            //           by delaying reset by reporting false in app_shutdown_handler
            NRF_LOG_INFO("Device will enter bootloader mode.");
            break;

        case BLE_DFU_EVT_BOOTLOADER_ENTER_FAILED:
            NRF_LOG_ERROR("Request to enter bootloader mode failed asynchroneously.");
            // YOUR_JOB: Take corrective measures to resolve the issue
            //           like calling APP_ERROR_CHECK to reset the device.
            break;

        case BLE_DFU_EVT_RESPONSE_SEND_ERROR:
            NRF_LOG_ERROR("Request to send a response to client failed.");
            // YOUR_JOB: Take corrective measures to resolve the issue
            //           like calling APP_ERROR_CHECK to reset the device.
            APP_ERROR_CHECK(false);
            break;

        default:
            NRF_LOG_ERROR("Unknown event from ble_dfu_buttonless.");
            break;
    }
}
......
/**@brief Function for initializing services that will be used by the application.
 */
static void services_init(void)
{
    ......
    // Initialize NUS.
    ......
    // Initialize DFU.
    ble_dfu_buttonless_init_t dfus_init = {0};

    dfus_init.evt_handler = ble_dfu_evt_handler;

    err_code = ble_dfu_buttonless_init(&dfus_init);
    APP_ERROR_CHECK(err_code);
}
......
/**@brief Application main function.
 */
int main(void)
{
    bool erase_bonds;
    ret_code_t err_code;
    
    // Initialize the async SVCI interface to bootloader before any interrupts are enabled.
    err_code = ble_dfu_buttonless_async_svci_init();
    APP_ERROR_CHECK(err_code);

    // Initialize.
    ......
}

// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu\pca10040\s132\config\sdk_config.h
//==========================================================
// <q> BLE_DFU_ENABLED  - Enable DFU Service.
#define BLE_DFU_ENABLED 1
```

函数ble_dfu_buttonless_async_svci_init 用于修改一些Bootloader 配置参数，比如为DFU mode 设置广播名称或对端绑定信息等等，该函数需要用到bootloader libraries 和svci libraries，因此还需要往工程中添加bootloader / svci libraries 相关的源文件和头文件路径如下（路径 .\libraries\svc 在该工程ble_app_uart_dfu 中已默认添加，按字母序排列未显示在下图窗口中）：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20210419215627432.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
尝试编译工程，提示"unknown type name 'nrf_dfu_set_adv_name_svci_async_t'"，跟踪该类型名发现需要设置宏NRF_DFU_TRANSPORT_BLE 为1，且我们需要使能SVCI 模块，我们在sdk_config 中并没有查到该宏名称，对照工程ble_app_buttonless_dfu 发现需要在工程配置中添加如下几个宏定义：
![添加DFU Transport 和SVCI 宏定义](https://img-blog.csdnimg.cn/20210420103406884.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
到这里工程就可以顺利编译完成了，但还有些代码需要添加更改，比如现在工程有两个BLE service（NUS + DFU），需要两个UUID（可查阅代码知，NUS_UUID为0x0001 、DFU_UUID 为0xFE59），同时需要更大的Attribute table 空间，修改相关配置如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu\pca10040\s132\config\sdk_config.h

// <h> BLE Stack configuration - Stack configuration parameters
//==========================================================
// <o> NRF_SDH_BLE_GATTS_ATTR_TAB_SIZE - Attribute Table size in bytes. The size must be a multiple of 4. 
#define NRF_SDH_BLE_GATTS_ATTR_TAB_SIZE 1600

// <o> NRF_SDH_BLE_VS_UUID_COUNT - The number of vendor-specific UUIDs. 
#define NRF_SDH_BLE_VS_UUID_COUNT 2
```

还需要添加Power Management library，注册并实现app_shutdown_handler，启用宏定义NRF_PWR_MGMT_CONFIG_AUTO_SHUTDOWN_RETRY 如下（参阅：[Adding Buttonless Secure DFU Service to a BLE application](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/service_dfu.html)）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu\main.c
......
// Add DFU service
#include "ble_dfu.h"
#include "nrf_power.h"
#include "nrf_bootloader_info.h"
......
/**@brief Handler for shutdown preparation.
 *
 * @details During shutdown procedures, this function will be called at a 1 second interval
 *          untill the function returns true. When the function returns true, it means that the
 *          app is ready to reset to DFU mode.
 *
 * @param[in]   event   Power manager event.
 *
 * @retval  True if shutdown is allowed by this power manager handler, otherwise false.
 */
static bool app_shutdown_handler(nrf_pwr_mgmt_evt_t event)
{
    switch (event)
    {
        case NRF_PWR_MGMT_EVT_PREPARE_DFU:
            NRF_LOG_INFO("Power management wants to reset to DFU mode.");
            // YOUR_JOB: Get ready to reset into DFU mode
            //
            // If you aren't finished with any ongoing tasks, return "false" to
            // signal to the system that reset is impossible at this stage.
            //
            // Here is an example using a variable to delay resetting the device.
            //
            // if (!m_ready_for_reset)
            // {
            //      return false;
            // }
            // else
            //{
            //
            //    // Device ready to enter
            //    uint32_t err_code;
            //    err_code = sd_softdevice_disable();
            //    APP_ERROR_CHECK(err_code);
            //    err_code = app_timer_stop_all();
            //    APP_ERROR_CHECK(err_code);
            //}
            break;

        default:
            // YOUR_JOB: Implement any of the other events available from the power management module:
            //      -NRF_PWR_MGMT_EVT_PREPARE_SYSOFF
            //      -NRF_PWR_MGMT_EVT_PREPARE_WAKEUP
            //      -NRF_PWR_MGMT_EVT_PREPARE_RESET
            return true;
    }

    NRF_LOG_INFO("Power management allowed to reset to DFU mode.");
    return true;
}

//lint -esym(528, m_app_shutdown_handler)
/**@brief Register application shutdown handler with priority 0.
 */
NRF_PWR_MGMT_HANDLER_REGISTER(app_shutdown_handler, 0);


static void buttonless_dfu_sdh_state_observer(nrf_sdh_state_evt_t state, void * p_context)
{
    if (state == NRF_SDH_EVT_STATE_DISABLED)
    {
        // Softdevice was disabled before going into reset. Inform bootloader to skip CRC on next boot.
        nrf_power_gpregret2_set(BOOTLOADER_DFU_SKIP_CRC);

        //Go to system off.
        nrf_pwr_mgmt_shutdown(NRF_PWR_MGMT_SHUTDOWN_GOTO_SYSOFF);
    }
}

/* nrf_sdh state observer. */
NRF_SDH_STATE_OBSERVER(m_buttonless_dfu_state_obs, 0) =
{
    .handler = buttonless_dfu_sdh_state_observer,
};


// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu\pca10040\s132\config\sdk_config.h
// <q> NRF_PWR_MGMT_CONFIG_AUTO_SHUTDOWN_RETRY  - Blocked shutdown procedure will be retried every second.
#define NRF_PWR_MGMT_CONFIG_AUTO_SHUTDOWN_RETRY 1
```

上面注册并实现的app_shutdown_handler 和buttonless_dfu_sdh_state_observer 并不是DFU service 必需的，app_shutdown_handler 主要是为了让应用在进入DFU mode 前做些准备工作，比如完成当前的flash 操作、关闭某些模块 等，Nordic SDK 文档要求添加该函数。Buttonless_dfu_sdh_state_observer 主要是为了加快应用程序的启动速度，当系统需要重置时，跳过bootloader CRC 校验过程。

为方便比较DFU 前后的版本，我们在工程ble_app_uart_dfu 中添加对端设备通过NUS 查询软件版本号的命令如下（为区别于示例工程ble_app_uart，将广播名改为"Nordic_UART_DFU"）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu\main.c
......
#define DEVICE_NAME                     "Nordic_UART_DFU"                           /**< Name of device. Will be included in the advertising data. */
#define SW_VERSION                      "1.0.0"                                     /**< Software Version. */
......
/**@brief Process the commands received by the NUS service. 
 */
static uint32_t nus_cmd_process(uint8_t const * p_data, uint16_t length)
{
    uint32_t err_code;

    // Processing command.
    if(p_data[0] == 's' && p_data[1] == 'w')
    {
        uint8_t sw_str[] = SW_VERSION;
        uint16_t sw_len = strlen(sw_str);

        do
        {
            err_code = ble_nus_data_send(&m_nus, sw_str, &sw_len, m_conn_handle);
            if ((err_code != NRF_ERROR_INVALID_STATE) &&
                (err_code != NRF_ERROR_RESOURCES) &&
                (err_code != NRF_ERROR_NOT_FOUND))
            {
                APP_ERROR_CHECK(err_code);
            }
        } while (err_code == NRF_ERROR_RESOURCES);
    }

    return err_code;
}


/**@brief Function for handling the data from the Nordic UART Service.
 */
static void nus_data_handler(ble_nus_evt_t * p_evt)
{

    if (p_evt->type == BLE_NUS_EVT_RX_DATA)
    {
        ......
        if (p_evt->params.rx_data.p_data[p_evt->params.rx_data.length - 1] == '\r')
            while (app_uart_put('\n') == NRF_ERROR_BUSY);

        // Process the commands received from the peer device.
        err_code = nus_cmd_process(p_evt->params.rx_data.p_data, p_evt->params.rx_data.length);
        APP_ERROR_CHECK(err_code);
    }
}
```

到这里，就完成了Buttonless DFU without bonds service 的添加，编译工程，顺利完成。将生成的ble_app_uart_pca10040_s132.hex 文件复制出来，按照[前篇博文的方法](https://blog.csdn.net/m0_37621078/article/details/115541552?spm=1001.2014.3001.5501#t4)执行生成Bootloader settings、合并烧录hex 文件的过程，手机端nRF Connect 软件并没有搜索到"Nordic_UART_DFU" 设备。通过J-Link RTT Viewer 工具查看Log，得知softdevice RAM 空间不足，需要修改RAM_START 和RAM_SIZE 的值如下：
![修改softdevice RAM start and size](https://img-blog.csdnimg.cn/20210420193952537.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
重新编译工程，生成Bootloader settings、合并烧录hex 文件到nRF52 DK 中，手机端nRF Connect 软件可以扫描并成功连接"Nordic_UART_DFU" 设备，在服务列表可以看到Secure DFU Service，使用Nordic UART Service 向"Nordic_UART_DFU" 设备发送查询软件版本的命令“sw”，可以正常收到软件版本号“1.0.0”（需先点击“Enable CCCDs”）：
![Add DFU Service and SW_VER command](https://img-blog.csdnimg.cn/20210420195144879.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
接下来尝试DFU Service 是否正常，我们修改宏定义SW_VERSION 值为“1.1.1”，重新编译工程，将生成的hex文件复制出来并重命名为ble_app_uart_pca10040_s132_v111.hex，执行DFU package 生成过程，获得DFU 升级包SDK1702_app_nus_dfu_s132_v111.zip，执行应用升级过程，结果如下：
![往工程中添加Buttonless DFU without bonds service 结果](https://img-blog.csdnimg.cn/20210420201443566.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
工程ble_app_uart_dfu 顺利完成DFU 过程，说明我们添加的Buttonless DFU without bonds service 可以正常使用。

## 2.2 如何为工程添加Buttonless DFU with bonds service？
Nordic infocenter [Buttonless Secure DFU Service](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/service_dfu.html) 提到，配对绑定过程需要借助 Peer Manager 模块管理对端设备信息。继续在infocenter 中查询[Peer Manager libraries](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/group__peer__manager.html)，得知Peer Manager 为了保存配对绑定信息到flash 中，需要使用FDS libraries。继续查询[Flash Data Storage (FDS)](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/lib_fds.html)，得知FDS libraries 需要用到Flash Storage (fstorage) libraries。

我们往工程ble_app_uart_dfu_bond 中添加Peer Manager、FDS libraries、fstorage libraries 的源文件与头文件路径如下（复制工程ble_app_uart_dfu 为ble_app_uart_dfu_bond，并在工程ble_app_uart_dfu_bond 基础上开发，头文件路径为方便显示临时调整了顺序）：
![往工程ble_app_uart_dfu_bond 中添加Peer Manager、FDS libraries、fstorage libraries 的源文件与头文件路径](https://img-blog.csdnimg.cn/20210420222538466.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
接下来添加函数peer_manager_init 的实现和调用，并注册相应的事件处理函数pm_evt_handler，再在sdk_config 中配置使能PEER_MANAGER、FDS、NRF_FSTORAGE 模块如下（从工程ble_app_buttonless_dfu 复制而来）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu_bond\main.c
......
// Add Bonding procedure
#include "peer_manager.h"
#include "peer_manager_handler.h"
#include "fds.h"
......
#define SEC_PARAM_BOND                  1                                           /**< Perform bonding. */
#define SEC_PARAM_MITM                  0                                           /**< Man In The Middle protection not required. */
#define SEC_PARAM_LESC                  0                                           /**< LE Secure Connections not enabled. */
#define SEC_PARAM_KEYPRESS              0                                           /**< Keypress notifications not enabled. */
#define SEC_PARAM_IO_CAPABILITIES       BLE_GAP_IO_CAPS_NONE                        /**< No I/O capabilities. */
#define SEC_PARAM_OOB                   0                                           /**< Out Of Band data not available. */
#define SEC_PARAM_MIN_KEY_SIZE          7                                           /**< Minimum encryption key size. */
#define SEC_PARAM_MAX_KEY_SIZE          16                                          /**< Maximum encryption key size. */
......
/**@brief Function for handling Peer Manager events.
 *
 * @param[in] p_evt  Peer Manager event.
 */
static void pm_evt_handler(pm_evt_t const * p_evt)
{
    pm_handler_on_pm_evt(p_evt);
    pm_handler_flash_clean(p_evt);
}


/**@brief Function for the Peer Manager initialization.
 */
static void peer_manager_init()
{
    ble_gap_sec_params_t sec_param;
    ret_code_t           err_code;

    err_code = pm_init();
    APP_ERROR_CHECK(err_code);

    memset(&sec_param, 0, sizeof(ble_gap_sec_params_t));

    // Security parameters to be used for all security procedures.
    sec_param.bond           = SEC_PARAM_BOND;
    sec_param.mitm           = SEC_PARAM_MITM;
    sec_param.lesc           = SEC_PARAM_LESC;
    sec_param.keypress       = SEC_PARAM_KEYPRESS;
    sec_param.io_caps        = SEC_PARAM_IO_CAPABILITIES;
    sec_param.oob            = SEC_PARAM_OOB;
    sec_param.min_key_size   = SEC_PARAM_MIN_KEY_SIZE;
    sec_param.max_key_size   = SEC_PARAM_MAX_KEY_SIZE;
    sec_param.kdist_own.enc  = 1;
    sec_param.kdist_own.id   = 1;
    sec_param.kdist_peer.enc = 1;
    sec_param.kdist_peer.id  = 1;

    err_code = pm_sec_params_set(&sec_param);
    APP_ERROR_CHECK(err_code);

    err_code = pm_register(pm_evt_handler);
    APP_ERROR_CHECK(err_code);
}
......
/**@brief Application main function.
 */
int main(void)
{
    ......
    ble_stack_init();
    peer_manager_init();
    gap_params_init();
    ......
}


// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu_bond\pca10040\s132\config\sdk_config.h
......
// <e> PEER_MANAGER_ENABLED - peer_manager - Peer Manager
//==========================================================
#define PEER_MANAGER_ENABLED 1
......
// <q> NRF_DFU_BLE_BUTTONLESS_SUPPORTS_BONDS  - Buttonless DFU supports bonds.
#define NRF_DFU_BLE_BUTTONLESS_SUPPORTS_BONDS 1
......
// <e> FDS_ENABLED - fds - Flash data storage module
//==========================================================
#define FDS_ENABLED 1
......
// <e> NRF_FSTORAGE_ENABLED - nrf_fstorage - Flash abstraction library
//==========================================================
#define NRF_FSTORAGE_ENABLED 1
......
```

我们使用蓝牙设备配对绑定功能时，会发现如果手机端配对绑定信息删除后，蓝牙设备会拒绝再次配对绑定，此时需要长按设备端某个按键使其再次进入配对绑定状态。实际上，这个过程是蓝牙设备端删除配对绑定信息，让蓝牙设备可以与手机建立新的配对绑定关系。我们使用 nRF52 DK 上的Button 2 作为删除绑定信息的按键，添加长按Button 2 擦除绑定信息的代码如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu_bond\main.c
......
/** @brief Clear bonding information from persistent storage.
 */
static void delete_bonds(void)
{
    ret_code_t err_code;

    NRF_LOG_INFO("Erase bonds!");

    err_code = pm_peers_delete();
    APP_ERROR_CHECK(err_code);
}

/**@brief Function for starting advertising.
 */
static void advertising_start(bool erase_bonds)
{
    if (erase_bonds == true)
    {
        delete_bonds();
        // Advertising is started by PM_EVT_PEERS_DELETE_SUCCEEDED event.
    }
    else
    {
        uint32_t err_code = ble_advertising_start(&m_advertising, BLE_ADV_MODE_FAST);
        APP_ERROR_CHECK(err_code);

        NRF_LOG_DEBUG("advertising is started");
    }
}

/**@brief Application main function.
 */
int main(void)
{
    ......
    advertising_start(erase_bonds);
    // Enter main loop.
    ......
}
```

[前篇博文](https://blog.csdn.net/m0_37621078/article/details/115541552?spm=1001.2014.3001.5501#t3)提到，Bonded DFU 过程中，DFU target 需要主动向DFU controller 发送service changed indication，让DFU controller 可以发现Bootloader 提供的DFU 服务，因此还需要启用NRF_SDH_BLE_SERVICE_CHANGED 如下（bootloader 和application 都需要启用该宏定义）：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu_bond\pca10040\s132\config\sdk_config.h
......
// <q> NRF_SDH_BLE_SERVICE_CHANGED  - Include the Service Changed characteristic in the Attribute Table.
#define NRF_SDH_BLE_SERVICE_CHANGED 1
......
```

编译工程，顺利完成，将生成的ble_app_uart_pca10040_s132.hex 文件复制出来，按照前篇博文的方法执行生成Bootloader settings、合并烧录hex 文件到nRF52 DK 中。手机端nRF Connect 软件可以扫描并成功连接"Nordic_UART_DFU" 设备，也可以借助Nordic UART Service 正常查询到软件版本，但执行配对绑定过程时提示“GATT CONN TIMEOUT”，也即无法建立配对绑定关系，这是什么原因导致的呢？

我们编译工程ble_app_uart_dfu_bond 的debug 版本，重新合并烧录到nRF52 DK 中，手机端nRF Connect 再次连接"Nordic_UART_DFU" 设备，执行绑定操作，从J-Link RTT Viewer 中看到如下错误提示：
![ble_app_uart_dfu_bond 的debug 版本 bond fail log](https://img-blog.csdnimg.cn/20210421004823984.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
J-Link RTT Viewer 提示main 函数第610 行NRF_ERROR_INVALID_STATE，该行对应的状态时是BLE_GAP_EVT_SEC_PARAMS_REQUEST，在当前工程中搜索该关键词，获知该状态或事件被重复处理了，我们将main 函数中该状态或事件相关的代码删除：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu_bond\main.c
......
/**@brief Function for handling BLE events.
 */
static void ble_evt_handler(ble_evt_t const * p_ble_evt, void * p_context)
{
    uint32_t err_code;

    switch (p_ble_evt->header.evt_id)
    {
        ......
        /*
        case BLE_GAP_EVT_SEC_PARAMS_REQUEST:
            // Pairing not supported
            err_code = sd_ble_gap_sec_params_reply(m_conn_handle, BLE_GAP_SEC_STATUS_PAIRING_NOT_SUPP, NULL, NULL);
            APP_ERROR_CHECK(err_code);
            break;
        */
        ......
    }
}
......

// .\nRF5_SDK_17.0.2_d674dde\components\ble\peer_manager\security_dispatcher.c
......
void smd_ble_evt_handler(ble_evt_t const * p_ble_evt)
{
    switch (p_ble_evt->header.evt_id)
    {
        ......
        case BLE_GAP_EVT_SEC_PARAMS_REQUEST:
            sec_params_request_process(&(p_ble_evt->evt.gap_evt));
            break;
		......
    };
}
......
```

重新编译该工程的release 版本，合并烧录到nRF52 DK 中，手机端nRF Connect 再次连接"Nordic_UART_DFU" 设备，执行绑定操作，可以正常绑定成功了。

接下来尝试DFU with bonds Service 是否正常，我们修改宏定义SW_VERSION 值为“2.2.2”，重新编译工程，将生成的hex文件复制出来并重命名为ble_app_uart_pca10040_s132_v222.hex，执行DFU package 生成过程，获得DFU 升级包SDK1702_app_nus_dfu_s132_v222.zip，执行应用升级过程，结果如下：
![往工程中添加Buttonless DFU with bonds service 结果](https://img-blog.csdnimg.cn/20210421011621353.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

我们在尝试Buttonless DFU with bonds procedure 时，发现手机端删除绑定信息后，若BLE 设备端没有擦除绑定信息，会拒绝手机端的配对绑定请求。前面也提到，可以通过长按Button 2 的情况下再按reset 来擦除绑定信息，如果我们开发的BLE 设备没有按键，有需要支持重新配对绑定该怎么办呢？

我们可以在网站[devzone.nordicsemi.com](https://devzone.nordicsemi.com/) 中搜索关键词“repair”，查得解决方案“[Connection to device (peripheral) after smartphone (central) erased its bonding data](https://devzone.nordicsemi.com/f/nordic-q-a/61528/connection-to-device-peripheral-after-smartphone-central-erased-its-bonding-data)” 如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_uart_dfu_bond\main.c
......
/**@brief Function for handling Peer Manager events.
 */
static void pm_evt_handler(pm_evt_t const * p_evt)
{
    pm_handler_on_pm_evt(p_evt);
    pm_handler_flash_clean(p_evt);

    // Add allow_repairing config
    if (p_evt->evt_id == PM_EVT_CONN_SEC_CONFIG_REQ)					/**< @brief The peer (central) has requested pairing, but a bond already exists with that peer. Reply by calling @ref pm_conn_sec_config_reply before the event handler returns. If no reply is sent, a default is used. */
    {
        pm_conn_sec_config_t config = {.allow_repairing = true};		/** @brief Whether to allow the peer to pair if it wants to, but is already bonded. If this is false, the procedure is rejected, and no more events are sent. Default: false. */
        pm_conn_sec_config_reply(p_evt->conn_handle, &config);
    }
}
......
```


本工程源码下载地址：[https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/BLE_NUS_DFU](https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/BLE_NUS_DFU)。


# 更多文章：

 - [《如何为BLE 设备实现OTA DFU 空中升级功能(上)？》](https://blog.csdn.net/m0_37621078/article/details/115541552)
 - [《如何实现BLE 最大数据吞吐率并满足设计功耗要求？》](https://blog.csdn.net/m0_37621078/article/details/115483595)
 - [《如何抓包分析BLE 空口报文(GAP + GATT + LESC)？》](https://blog.csdn.net/m0_37621078/article/details/115181768)
 - [《如何实现扫码连接BLE 设备的功能?》](https://blog.csdn.net/m0_37621078/article/details/107193411)
 - [《Nordic_nRF5_Project》](https://github.com/StreamAI/Nordic_nRF5_Project)
 - [《Nordic nRF5 SDK documentation》](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/index.html)
 - [《BLE 技术（五）--- Generic Access Profile + Pairing and Bonding》](https://blog.csdn.net/m0_37621078/article/details/107850523)
 - [《BLE 技术（六）--- GATT Profile + Security Manager Protocol》](https://blog.csdn.net/m0_37621078/article/details/108391261)
 - [《Bluetooth Core Specification_v5.2》](https://www.bluetooth.com/specifications/bluetooth-core-specification/)