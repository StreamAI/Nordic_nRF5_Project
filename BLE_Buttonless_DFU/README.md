# 如何为BLE 设备实现OTA DFU 空中升级功能（上）？
@[TOC]

> 我们开发的BLE peripheral 设备通常都有代码升级的需求，不管是解决先前的bug，还是增加新的功能。我们常用的PC 或手机都是直接联网在线升级系统或软件的，BLE 这类不直接接入互联网且人机交互受限的嵌入式设备如何升级程序代码呢？很多BLE peripheral 仅留出一个BLE 无线通讯接口，我们如何通过OTA 方式实现BLE 程序代码的空中升级呢？我们如何将DFU OTA 功能或服务作为一个模块添加进我们的工程中呢？

# 一、BLE peripheral 如何实现DFU？
在博文[ARM 代码烧录方案与原理详解](https://blog.csdn.net/m0_37621078/article/details/106798909) 中谈到，要实现DFU(Device Firmware Update)  功能一般需要bootloader 启动引导代码，且bootloader 与application 代码是存储在不同flash 区域的。

## 1.1 Nordic Memory layout
如果开发过Nordic 工程，我们知道蓝牙协议栈softdevice 和application 代码也是存储在不同flash 区域的。DFU 实际上就是把新的程序代码下载到本地设备，经校验通过后，搬移到原程序代码存储区的过程。我们要了解DFU 工作原理，需要先了解nordic memory 布局：
![Nordic Memory layout](https://img-blog.csdnimg.cn/20210409201206732.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)
Nordic memory 主要分为四个部分：

 - **Application**：我们实现业务逻辑的应用程序代码存放在该区域，用户需要掉电保护的一些自定义数据存储在Application data 区域，free 区域可用于暂存接收到的待升级固件代码、也可用于暂存本设备产生的数据；
 - **SoftDevice（BLE Protocol Stack）**：Nordic 以HEX 文件形式提供的BLE 协议栈代码存放在该区域，我们根据芯片型号、SDK版本、业务需求等因素选择合适的softdevice 版本；
 - **MBR(Master Boot Record)**：Nordic 引入MBR 主要是为了能借助DFU 更新Bootloader（我们可以借助Bootloader 将新的Application、Softdevice 或Bootloader 固件下载到某个Flash 空闲区域，完成校验后使用新的固件代码覆盖原来的代码，但bootloader 无法覆盖自身，需要借助MBR 完成新bootloader 固件覆盖旧代码的任务），		系统上电都是从MBR 启动的，所有的中断异常也都是首先由MBR 处理再转发给相应的处理程序，因此MBR 也管理系统启动流程，判断是否有bootloader 代码决定后续启动bootloader 还是直接启动application（MBR 代码不可更新）；
 - **MBR parameter storage**：当Bootloader 需要更新自身时，将新的bootloader 固件下载到本设备flash 空闲区域并完成校验后，需要借助MBR 搬移新固件以覆盖旧代码。Bootloader 需要MBR 执行哪些指令以及指令参数如何设置，这些信息都保存在MBR parameter storage 区域（由于从bootloader 切换到MBR 需系统重置，这些指令及参数需要保存在Flash 中而非RAM 中）；
 - **Bootloader**：主要用于更新固件代码（比如application、softdevice、bootloader），当我们有固件更新需求时，通过按键或者命令触发设备进入DFU 模式，bootloader 通过BLE、UART 或USB 方式将新的固件存储到本设备空闲flash 内（bootloader 可完全访问softdevice 的API）， 对新的固件进行校验（比如私钥签名校验、Hash 完整性校验、CRC 校验等），校验通过后搬移新的固件以覆盖旧的固件（搬移bootloader 固件需借助MBR），然后激活新的固件，引导执行 application；
 - **Bootloader settings**：主要配合bootloader 完成DFU 过程，在Bootloader settings 区域记录当前固件的版本 / 大小 / CRC 值、设备广播名与绑定信息、固件校验信息（CRC32 值、SHA-256 哈希值、ECDSA_P256 数字签名等）、固件更新进度、固件激活进度 等信息。为了防止在写入 Bootloader settings（DFU 过程需要读写该区域信息） 时发生复位或掉电影响DFU 过程，SDK15 以后的版本引入了settings backup 机制（实际上就是复用了MBR parameter storage 区域），当写入Bootloader settings 时发生复位或掉电重启后，可以从settings backup 区域读取备份信息恢复DFU 过程。

由于MBR 需要知道Bootloader、MBR parameter storage、SoftDevice、Application 代码的存储地址，Bootloader 也需要知道Bootloader settings、MBR parameter storage 信息的存储地址，上面每个存储区域的地址范围对于确定的Nordic 芯片和Softdevice 版本都有默认值（主要是不同Nordic 芯片可供Application 使用得flash 空间大小不同，不同版本的softdevice 代码占用flash 空间大小不同）：
![nordic Memory range](https://img-blog.csdnimg.cn/20210413193607717.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

## 1.2 Device Firmware Update process
 BLE 连接通信需要两个设备BLE Peripheral / Slave 和BLE Central / Master，DFU 过程也需要两个设备DFU target 和 DFU controller。DFU target 是要接收新的固件并升级固件的设备（比如手环、心率带等），DFU controller 是发送新的固件并控制升级过程的设备（比如手机、网关等）。DFU 固件升级流程图如下：
![Process flow on the DFU target](https://img-blog.csdnimg.cn/20210413193902672.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)
首先，进入DFU mode 的方式有如下四种：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\dfu\secure_bootloader\pca10040_s132_ble\config\sdk_config.h

// <h> DFU mode enter method 
//==========================================================
// <e> NRF_BL_DFU_ENTER_METHOD_BUTTON - Enter DFU mode on button press.
#define NRF_BL_DFU_ENTER_METHOD_BUTTON 1

// <q> NRF_BL_DFU_ENTER_METHOD_PINRESET  - Enter DFU mode on pin reset.
#define NRF_BL_DFU_ENTER_METHOD_PINRESET 0

// <q> NRF_BL_DFU_ENTER_METHOD_GPREGRET  - Enter DFU mode when bit 0 is set in the NRF_POWER_GPREGRET register.
#define NRF_BL_DFU_ENTER_METHOD_GPREGRET 1

// <q> NRF_BL_DFU_ENTER_METHOD_BUTTONLESS  - Enter DFU mode when the Boolean enter_buttonless_dfu in DFU settings is true.
#define NRF_BL_DFU_ENTER_METHOD_BUTTONLESS 0
```

比较常用的是下面这两种方式：

 - **按键式ButtonPress DFU**：DFU target 上电时长按某个按键进入DFU 模式，适合有按键的设备使用；
 - **非按键式Buttonless DFU**：DFU target 接收到命令后自动进入DFU 模式，整个升级过程DFU target 不需要任何人工干预，适合完全封装无按键的设备使用。该方式需要DFU target application 能够接收并处理进入DFU 模式的命令，Nordic SDK 示例工程 ble_app_buttonless_dfu 可以在接收到来自DFU controller 的升级命令后，将寄存器NRF_POWER->GPREGRET bit 0 设置为1，系统触发软件复位，从MBR 启动Bootloader，Bootloader 检测到满足进入DFU mode 的条件（NRF_POWER->GPREGRET 值为0xB1），便进入DFU 模式开始固件升级过程。

DFU target 进入DFU mode 后，开始等待接收数据，这里分为两个阶段：

 - **Receive init packet and Prevalidation**：DFU target 先接收到init packet，主要包含firmware 类型、大小、版本、hash 值、固件支持的硬件版本和softdevice ID、固件签名类型及数字签名等信息，DFU target 接收完init packet 后对这些信息进行前期Prevalidation，主要是校验待升级的固件是否由受信任方提供、是否跟当前固件和硬件兼容等。如果预校验通过，则更新Bootloader settings page 并准备开始接收firmware；
 - **Receive firmware and Postvalidation**：DFU target Prevalidation OK 后，开始接收firmware data，每接收4 KB 数据（也即1 page）回复一次CRC 校验值，直到整个固件接收完毕，对其进行Postvalidation，主要是Hash 完整性校验。如果后期校验通过，就会invalidate 无效化当前固件，更新Bootloader settings page 并触发软件复位。

固件传输过程，根据传输方式的不同，可以分为有线升级和无线升级两种：

 - **Wired DFU**：通过有线通信方式来传输固件，比如UART、USB 等（目前Nordic SDK 仅对nRF52840 支持USB DFU）；
 - **Wireless DFU(OTA DFU)**：通过无线通信方式来传输固件，比如BLE、ANT 等。

固件校验过程，根据是否需要校验[数字签名](https://blog.csdn.net/m0_37621078/article/details/106028622?spm=1001.2014.3001.5502#t7)，也可分为开放升级和安全升级两种：

 - **Open DFU**：不对新的固件进行数字签名校验（bootloader 除外），且优先使用Single-bank 升级方式（目前Nordic SDK 仅支持通过USB 传输固件的方式进行Open DFU）；
 - **Secure DFU**：需要对新的固件进行数字签名校验，以防止恶意攻击者伪造固件被接受并升级，特别是对OTA DFU 应要求数字签名校验（Nordic SDK 建议对所有固件进行数字签名校验）。

完成固件传输和校验后，就开始进行copy new firmware 的过程了，实际上就是使用新的固件覆盖旧的固件。根据新固件和旧固件占用的存储分区个数，可分为双分区升级和单分区升级两种：

 - **Dual-bank DFU**：将接收到的新固件先暂存在空闲存储区Bank 1 中，完成数字签名校验和完整性校验后，再擦除现有固件代码（假设存储在Bank 0 中），然后将Bank 1 中的新固件复制到Bank 0 处并激活（如果新固件校验失败，不影响现有固件的正常运行）。双分区升级需要足够的空闲存储区Bank 1 来存储新固件，对存储空间的要求较高，如果空闲存储区不足以存储新固件，则根据配置选择是拒绝升级还是转为单分区升级。下图左边展示了SoftDevice + Bootloader 的双分区升级过程，右边展示了Application 的双分区升级过程：
![DFU flash operations for a dual-bank update](https://img-blog.csdnimg.cn/20210414011108737.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
 - **Single-bank DFU**：进入DFU 模式后先擦除当前application 代码，再把接收到的新固件存储到原应用所在的Bank 0 中（实际上相当于直接使用新应用替换旧应用代码），新固件接收完毕并通过校验后直接激活（如果新固件校验失败，系统将保持DFU 模式继续尝试再次升级，因为原应用程序已被擦除而不能再执行）。单分区升级相比双分区升级节省了一个Bank 空间，在系统资源比较紧张的情况下可以选用，Nordic SDK 默认优先使用双分区升级方案。下图左边展示了SoftDevice + Bootloader 的单分区升级过程（因该过程会擦除application，完成SoftDevice + Bootloader 升级后还需要再进行application 升级），右边展示了Application 的单分区升级过程：
![DFU flash operations for a single-bank update](https://img-blog.csdnimg.cn/20210414011314970.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

设备固件升级过程中，工程pca10040_s132_ble 中跟固件传输方式、固件版本校验、固件签名校验、固件单双区升级控制 等相关的宏变量配置如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\dfu\secure_bootloader\pca10040_s132_ble\config\sdk_config.h

// <e> NRF_DFU_TRANSPORT_BLE - BLE transport settings
//==========================================================
#define NRF_DFU_TRANSPORT_BLE 1
// <s> NRF_DFU_BLE_ADV_NAME - Default advertising name.
#define NRF_DFU_BLE_ADV_NAME "DfuTarg"

// <h> DFU security - nrf_dfu_validation - DFU validation
//==========================================================
// <q> NRF_DFU_APP_ACCEPT_SAME_VERSION  - Whether to accept application upgrades with the same version as the current application.
#define NRF_DFU_APP_ACCEPT_SAME_VERSION 1
// <q> NRF_DFU_APP_DOWNGRADE_PREVENTION  - Check the firmware version and SoftDevice requirements of application (and SoftDevice) updates.
#define NRF_DFU_APP_DOWNGRADE_PREVENTION 1
// <q> NRF_DFU_EXTERNAL_APP_VERSIONING  - Require versioning for external applications.
#define NRF_DFU_EXTERNAL_APP_VERSIONING 1
// <o> NRF_DFU_HW_VERSION - Device hardware version. 
#define NRF_DFU_HW_VERSION 52

// <q> NRF_DFU_REQUIRE_SIGNED_APP_UPDATE  - Require a valid signature to update the application or SoftDevice.
#define NRF_DFU_REQUIRE_SIGNED_APP_UPDATE 1

// <q> NRF_DFU_FORCE_DUAL_BANK_APP_UPDATES  - Accept only dual-bank application updates.
#define NRF_DFU_FORCE_DUAL_BANK_APP_UPDATES 0
// <q> NRF_DFU_SINGLE_BANK_APP_UPDATES  - Place the application and the SoftDevice directly where they are supposed to be.
#define NRF_DFU_SINGLE_BANK_APP_UPDATES 0

// <h> BLE DFU security 
//==========================================================
// <q> NRF_DFU_BLE_REQUIRES_BONDS  - Require bond with peer.
#define NRF_DFU_BLE_REQUIRES_BONDS 0
```

Nordic SDK 提供的secure_bootloader 工程pca10040_s132_ble，默认优先采用Dual-bank DFU 方式，当没有足够的空闲flash 空间时将切换到Single-bank DFU 方式，开发者可配置宏变量NRF_DFU_FORCE_DUAL_BANK_APP_UPDATES 为1 强制使用Dual-bank DFU （若空间不足则停止DFU 过程）。

Nordic SDK 默认提供的是后台式升级，对于工程ble_app_buttonless_dfu 来说，系统有两段完全独立的代码：Application 和Bootloader，其中SoftDevice 是共用的，两段独立的程序都可以访问SoftDevice API，也都有自己的蓝牙广播和蓝牙连接。当需要进行DFU 时，在Application 中触发进入DFU mode，后面就交由Bootloader 完成固件的传输、校验、激活过程。当DFU target 从Application 跳转到Bootloader 后，DFU controller 怎么判断两者是同一个设备呢？

DFU controller 可以通过相同的广播名或设备地址来辨识出DFU target 的Application 连接和Bootloader 连接来自同一设备，但由于多数手机为了加快BLE 连接速度，常将首次连接发现的GATT Service 缓存到本地，下次连接若判断为同一设备就会跳过服务发现过程直接从缓存读取服务数据，这就导致DFU controller 不能发现Bootloader 提供的DFU 服务，也就无法顺利完成DFU 过程。由此可见，DFU controller 应不仅能辨识Application 连接和Bootloader 连接来自同一设备，还需要辨识当前连接是Application 连接还是Bootloader 连接，这个问题该如何解决呢？

Nordic 为该问题提供了两套方案：

 - **Unbonded DFU**：DFU target 设备Application 和Bootloader 程序采用不同的蓝牙设备地址，且Bootloader 程序的蓝牙设备地址 = Application 程序的蓝牙设备地址 + 1，这样DFU controller 就可以区分Application 连接和Bootloader 连接，同时辨识出二者来自同一设备，由于蓝牙设备地址不同，DFU controller 也会对Bootloader 连接执行服务发现过程，发现Bootloader 提供的DFU 服务，继续进行DFU 过程；
 - **Bonded DFU**：DFU target 设备Application 和Bootloader 程序采用相同的蓝牙设备地址，由于DFU target 和DFU controller 进行了配对绑定过程，DFU target 可以主动向DFU controller 发送service changed indication，让DFU controller 再执行一次服务发现过程，让DFU controller 可以发现Bootloader 提供的DFU 服务，继续进行DFU 过程。

# 二、如何实现Buttonless OTA DFU？
对于BLE peripheral，通常都是电池供电，因此对其进行固件升级通常都采用OTA DFU 方式（也即BLE DFU）。很多BLE peripheral 并没有留出按键，需要人工干预的升级方式也不够友好，因此BLE DFU 更多采用Buttonless DFU 方式升级固件。

本文使用的开发工具和示例工程如下：

 - **Development Kit**：[nRF52 DK](https://www.nordicsemi.com/Software-and-tools/Development-Kits/nRF52-DK/Download#infotabs);
 - **nRF5 SDK**：[nRF5_SDK_17.0.2_d674dde](https://www.nordicsemi.com/Software-and-tools/Software/nRF5-SDK/Download#infotabs)
 - **SoftDevice**：s132_nrf52_7.2.0_softdevice.hex
 - **Bootloader**：secure_bootloader_ble_s132_pca10040
 - **Application**：ble_app_buttonless_dfu_pca10040_s132
 - **nRF Command Line Tools**：[nRF-Command-Line-Tools_10_10_0_Installer_64.exe](https://www.nordicsemi.com/Software-and-Tools/Development-Tools/nRF-Command-Line-Tools/Download#infotabs)（包含J-Link、nrfjprog、mergehex 命令集，可用于Nordic Soc 开发、烧录 和调试）
 - **nRF Util**：[nrfutil-6.1.0.exe](https://github.com/NordicSemiconductor/pc-nrfutil/releases/tag/v6.1)（提供[nrfutil 命令集](https://infocenter.nordicsemi.com/topic/ug_nrfutil/UG/nrfutil/nrfutil_intro.html)，可用于DFU package生成、Cryptographic key生成/管理/存储、Bootloader settings 生成等），需[Python 3.7 or later](https://www.python.org/downloads/) 支持
 - **Other Tools**：[Setup_EmbeddedStudio_ARM_v540b_win_x64.exe](https://www.segger.com/downloads/embedded-studio)，[nRF Connect-v4.24.3.apk](https://github.com/NordicSemiconductor/Android-nRF-Connect/releases/tag/v4.24.3)，[nRF Connect-setup-v3.6.1-ia32.exe](https://www.nordicsemi.com/Software-and-tools/Development-Tools/nRF-Connect-for-desktop/Download#infotabs)，[nRF.Toolbox.2.9.0.apk](https://github.com/NordicSemiconductor/Android-nRF-Toolbox/releases/tag/v2.9.0)

## 2.1 如何使用SDK 提供的Buttonless BLE DFU 示例？
要实现无按键式的BLE 空中升级，需要往nRF52 DK 中烧录SoftDevice（包含MBR）、Bootloader、Application 三部分。由于在DFU 过程中需要对新固件进行Prevalidation 和Postvalidation，校验过程主要是信息比对，Bootloader settings page 保存了当前固件的属性及校验信息，init packet 包含了新固件的属性及校验信息。因此，首次向nRF52 DK 中烧录Bootloader 和Application 时，也应包含Bootloader settings page 信息（可由nrfutil 生成），制作DFU package 也应包含固件版本及校验信息（可由nrfutil 生成）。

 1. **Install nrf_crypto backend(micro-ecc)**

首先，我们打开工程secure_bootloader_ble_s132_pca10040，编译提示“uECC.h: No such file or directory”，我们在[infocenter.nordicsemi.com](https://infocenter.nordicsemi.com/index.jsp) 搜索关键词“uECC” 得知[micro_ecc backend](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/lib_crypto_backend_micro_ecc.html) 需要安装（可能受限于版权要求，不能直接放到SDK 中），在.\nRF5_SDK_17.0.2_d674dde\external\micro-ecc 目录下有自动化脚本build_all.bat，我们直接执行该脚本即可自动安装micro_ecc 密码库（需要电脑安装Git、make 命令集和GCC compiler toolchain for ARM），安装完成后会多一个micro-ecc 文件夹，里面就有uECC.h 文件和uECC.c 文件：
![在这里插入图片描述](https://img-blog.csdnimg.cn/20210414231225766.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
Nordic [Cryptography library - nrf_crypto](https://infocenter.nordicsemi.com/topic/sdk_nrf5_v17.0.2/lib_crypto.html) 分为nrf_crypto frontend 和nrf_crypto backends 两部分，nrf_crypto frontend 对应用程序提供统一的API，隐藏了不同nrf_crypto backends 的API 差异。我们可以根据硬件资源、版权等要求选择合适的nrf_crypto backends，比如nRF52840 支持Arm CryptoCell CC310 cryptographic accelerator 建议选用CC310 backend（配合CryptoCell CC310 可以提高加解密效率），其它nRF52 芯片建议优先选用micro-ecc backend（占用的存储空间更小），若micro-ecc 无法满足需求且不支持CryptoCell CC310 可选用mbed TLS backend（ARM 为嵌入式设备开发的支持[TLS 协议](https://blog.csdn.net/m0_37621078/article/details/106028622)的加解密算法，功能比micro-ecc 更强大）：
![Basic layout nrf_crypto frontend, backend, and source or library](https://img-blog.csdnimg.cn/2021041500285563.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)
工程secure_bootloader_ble_s132_pca10040 的sdk_config.h 中跟nrf_crypto 配置相关的宏变量如下（通过插件CMSIS_Configuration_Wizard.jar 查看sdk_config.h）：
![secure_bootloader_ble_s132_pca10040 sdk_config](https://img-blog.csdnimg.cn/20210414234417259.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)

 2. **Generating DFU public/private key pair**

继续编译工程secure_bootloader_ble_s132_pca10040，提示#error "Debug public key not valid for production. Please see https://github.com/NordicSemiconductor/pc-nrfutil/blob/master/README.md to generate it"，大意是说dfu_public_key.c 文件中的公钥是无效的，需要我们使用nrfutil 工具重新生成公私密钥对。

如何利用nrfutil 生成公私密钥对呢？我们可以查看Nordic 在线文档[Generating and displaying keys](https://infocenter.nordicsemi.com/topic/ug_nrfutil/UG/nrfutil/nrfutil_keys_generate_display.html)，也可以使用nrfutil keys --help 命令，获知生成公私密钥对的命令如下：

```bash
# Generate a private key and store it in a file named private.pem
nrfutil keys generate private.pem

# Display the public key that corresponds to the generated private key (in code format to be used with DFU)
nrfutil keys display --key pk --format code private.pem

# Write the public key that corresponds to the generated private key to the file public_key.c (in code format)
nrfutil keys display --key pk --format code private.pem --out_file dfu_public_key.c
```

该工程中的公钥用于验证DFU package 的数字签名，与该公钥配对的私钥则用于为DFU package 进行数字签名。由于DFU 过程主要靠签名校验判断固件升级包来源的可信性，为了保证DFU 过程的安全性，我们需要保管好生成的私钥，后续每次升级固件都需要该私钥对其签名。

我们将生成的公钥文件dfu_public_key.c 放到目录.\nRF5_SDK_17.0.2_d674dde\examples\dfu 下并替换原有的同名文件。继续编译工程secure_bootloader_ble_s132_pca10040，这次工程顺利编译完成，将编译生成的secure_bootloader_ble_s132_pca10040.hex 文件复制出来，这就是我们实现Buttonless BLE DFU 的Bootloader 程序代码。

我们打开工程ble_app_buttonless_dfu_pca10040_s132，编译完成后，将生成的ble_app_buttonless_dfu_pca10040_s132.hex 文件复制出来，这就是我们实现Buttonless BLE DFU 的Application 代码。

SoftDevice 不需要我们编译，Nordic SDK 直接提供的HEX 文件，我们从目录.\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\hex 将s132_nrf52_7.2.0_softdevice.hex 文件复制出来，这就是我们实现Buttonless BLE DFU 的SoftDevice 代码。

 3. **Generating Bootloader settings HEX**

准备好SoftDevice、Bootloader、Application 代码文件，为方便后续DFU 过程的固件校验，还需要生成包含固件版本等属性信息的Bootloader settings 文件。

如何利用nrfutil 生成Bootloader settings 呢？我们可以查看Nordic 在线文档[Generating and displaying bootloader settings](https://infocenter.nordicsemi.com/topic/ug_nrfutil/UG/nrfutil/nrfutil_settings_generate_display.html)，也可以使用nrfutil settings generate --help 命令，获知生成Bootloader settings的命令如下：

```bash
# Generate a bootloader settings page for an nRF52 device with the application ble_app_buttonless_dfu_pca10040_s132.hex installed, with application version string “1.0.0”, bootloader version 1, and bootloader settings version 2 (for SDK v17.0.2), and store it in a file named bl-settings.hex:
nrfutil settings generate --family NRF52 --application ble_app_buttonless_dfu_pca10040_s132.hex --application-version-string "1.0.0" --bootloader-version 1 --bl-settings-version 2  bl-settings.hex

# display the contents of the generated HEX file:
nrfutil settings display bl-settings.hex
```

生成实现Buttonless BLE DFU 功能的Bootloader settings 文件都包含哪些信息呢？我们可以查看生成的bl-settings.hex 文件内容如下：
![nrfutil settings display bl-settings.hex](https://img-blog.csdnimg.cn/20210415163248999.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)
每个字段的含义都可以在struct nrf_dfu_settings_t 中查得，该数据结构的声明如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\components\libraries\bootloader\dfu\nrf_dfu_types.h

/**@brief DFU settings for application and bank data.
 */
typedef struct
{
    uint32_t            crc;                /**< CRC for the stored DFU settings, not including the CRC itself. If 0xFFFFFFF, the CRC has never been calculated. */
    uint32_t            settings_version;   /**< Version of the current DFU settings struct layout. */
    uint32_t            app_version;        /**< Version of the last stored application. */
    uint32_t            bootloader_version; /**< Version of the last stored bootloader. */

    uint32_t            bank_layout;        /**< Bank layout: single bank or dual bank. This value can change. */
    uint32_t            bank_current;       /**< The bank that is currently used. */

    nrf_dfu_bank_t      bank_0;             /**< Bank 0. */
    nrf_dfu_bank_t      bank_1;             /**< Bank 1. */

    uint32_t            write_offset;       /**< Write offset for the current operation. */
    uint32_t            sd_size;            /**< Size of the SoftDevice. */

    dfu_progress_t      progress;           /**< Current DFU progress. */

    uint32_t            enter_buttonless_dfu;
    uint8_t             init_command[INIT_COMMAND_MAX_SIZE];  /**< Buffer for storing the init command. */

    uint32_t            boot_validation_crc;
    boot_validation_t   boot_validation_softdevice;
    boot_validation_t   boot_validation_app;
    boot_validation_t   boot_validation_bootloader;

    nrf_dfu_peer_data_t peer_data;          /**< Not included in calculated CRC. */
    nrf_dfu_adv_name_t  adv_name;           /**< Not included in calculated CRC. */
} nrf_dfu_settings_t;
```

 4. **Merge and program hex files**

我们已经生成了需要烧录到nRF52 DK 中实现Buttonless BLE DFU 功能的四个程序文件，四个文件分别烧录略繁琐，我们可以先将其合并为一个hex 文件，再将其烧录到目标芯片中。

我们可以使用mergehex 命令实现多个hex 文件的合并，可以查看Nordic 在线文档[Merging files with mergehex](https://infocenter.nordicsemi.com/topic/ug_nrf_cltools/UG/cltools/nrf_mergehex.html)，也可以使用mergehex --help 命令，获知合并多个hex 文件的命令如下：

```bash
# Merge four HEX files into one file named all_ble_buttonless_dfu_nrf52832_s132.hex
 mergehex --merge s132_nrf52_7.2.0_softdevice.hex secure_bootloader_ble_s132_pca10040.hex bl-settings.hex ble_app_buttonless_dfu_pca10040_s132.hex --output all_ble_buttonless_dfu_nrf52832_s132.hex
```

使用mergehex 命令将softdevice、bootloader、settings、application 合并为一个文件all_ble_buttonless_dfu_nrf52832_s132.hex 后，可以使用nrfjprog 命令将其烧录到nRF52 DK 中（也可以使用nRF Connect for desktop --> Programmer 烧录hex 文件）。我们可以查看Nordic 在线文档[Programming SoCs with nrfjprog](https://infocenter.nordicsemi.com/topic/ug_nrf_cltools/UG/cltools/nrf_nrfjprogexe.html)，也可以使用nrfjprog --help 命令，获知将hex 文件烧录到目标芯片中的命令如下：

```bash
# Erase all available user flash (including UICR) and program the file all_ble_buttonless_dfu_nrf52832_s132.hex to an nRF52 SoC
nrfjprog --family NRF52 --program all_ble_buttonless_dfu_nrf52832_s132.hex --chiperase --verify --reset
```

我们借助上面提供的nrfjprog 命令将合并后的代码文件all_ble_buttonless_dfu_nrf52832_s132.hex 烧录到nRF52 DK 中，系统正常启动，我们可以通过nRF Connect 扫描并发现“Nordic_Buttonless” 设备。点击“Connect” 连接成功后，可以看到“Secure DFU Service” 服务，该服务包含“Buttonless DFU” Characteristic，下文尝试使用该服务执行BLE DFU 空中升级过程。

## 2.2 如何执行Buttonless BLE DFU 过程？
要使用“Secure DFU Service” 进行空中升级，还需要准备DFU package。通常Bootloader 和Softdevice 更新频率很低，Application 更新频率较高，本文以空中升级application 固件为例，说明Buttonless BLE DFU 过程。

版本更新，最直观的判断标识是版本号，工程ble_app_buttonless_dfu_pca10040_s132 暂不支持查询软件版本的命令，为了更直观辨识新旧版本的差异，我们修改该工程的广播名称，原广播名为"Nordic_Buttonless"，我们修改为"Nordic_DFU_V110"：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_buttonless_dfu\main.c
#define DEVICE_NAME                     "Nordic_DFU_V110"                           /**< Name of device. Will be included in the advertising data. */
```

重新编译工程，将生成的hex 文件添加版本号，修改后的app 文件为ble_app_buttonless_dfu_pca10040_s132_v110.hex，然后使用nrfutil 工具生成DFU package。

如何利用nrfutil 生成DFU package 呢？我们可以查看Nordic 在线文档[Generating DFU packages](https://infocenter.nordicsemi.com/topic/ug_nrfutil/UG/nrfutil/nrfutil_pkg.html)，也可以使用nrfutil pkg generate --help 命令，获知生成DFU package 的命令如下：

```bash
# Generate a package called SDK1702_app_s132_v110.zip from the application file ble_app_buttonless_dfu_pca10040_s132_v110.hex with application version "1.1.0" that requires hardware version 52 and SoftDevice S132 v7.2.0 (0x0101) and is signed with the private key that is stored in private.pem
nrfutil pkg generate --application ble_app_buttonless_dfu_pca10040_s132_v110.hex --application-version-string "1.1.0" --hw-version 52 --sd-req 0X0101 --key-file private.pem SDK1702_app_s132_v110.zip

# Display the contents of the created dfu package SDK1702_app_s132_v110.zip
nrfutil pkg display SDK1702_app_s132_v110.zip
```

值得一提的是，nrfutil pkg generate 命令 “--sd-req” 参数需要制定SoftDevice firmware ID，帮助界面给出的列表并没有包含s132_nrf52_7.2.0，我们该如何获得s132_nrf52_7.2.0 的firmware ID 呢？到s132 所在的目录 .\nRF5_SDK_17.0.2_d674dde\components\softdevice\s132\doc\s132_nrf52_7.2.0_release-notes.pdf，可以查得：

> The Firmware ID of s132_nrf52_7.2.0 is **0x0101**.


我们可以通过nrfutil pkg display ZIP_FILE 命令查看DFU package 的内容，主要是 init packet file 和 firmware image file 相关的信息如下：

![nrfutil pkg display SDK1702_app_nrf52832_s132.zip](https://img-blog.csdnimg.cn/20210415181529771.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70#pic_center)
由于各部分hex 文件名都比较长，上面的命令也比较长，我们可以将其编辑进shell 脚本里面（对于windows 系统就是.bat 批处理文件 ），后续制作DFU package 只需要执行脚本即可：
![generate_settings_and_merge_program_shell](https://img-blog.csdnimg.cn/20210415193956359.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

 - **Unbonded BLE DFU procedure**

有了DFU package（SDK1702_app_s132_v110.zip），我们就可以使用“Secure DFU Service” 进行空中升级了，比如使用手机端nRF Connect for mobile 扫描发现并连接“Nordic_Buttonless” 设备 --> 点击“DFU” 图标 --> 选择DFU package（SDK1702_app_s132_v110.zip）便开始DFU 过程（需将DFU package 传到手机上），DFU 完成后设备广播名变为"Nordic_DFU_V110"，说明固件升级成功了，操作图示如下：
![nRF Connect for mobile Unbonded BLE DFU procedure](https://img-blog.csdnimg.cn/20210415224955824.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)
注意上图“Nordic_Buttonless” 和“DFUTARG” 的蓝牙设备地址关系，印证了前面介绍的Unbonded DFU 过程中DFU target 设备Bootloader 程序的蓝牙设备地址 = Application 程序的蓝牙设备地址 + 1，方便DFU controller 区分Application 连接和Bootloader 连接，发现Bootloader 提供的DFU 服务。

 - **Bonded BLE DFU procedure**

Bootloader 如果启用了NRF_DFU_BLE_REQUIRES_BONDS，则在执行BLE DFU 前需要先执行配对绑定过程，DFU target 拒绝来自未绑定DFU controller 的DFU 请求，Bonded DFU 安全性比Unbonded DFU 更高。我们在工程secure_bootloader_ble_s132_pca10040 中均启用NRF_DFU_BLE_REQUIRES_BONDS 如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\dfu\secure_bootloader\pca10040_s132_ble\config\sdk_config.h
// <h> BLE DFU security 
//==========================================================
// <q> NRF_DFU_BLE_REQUIRES_BONDS  - Require bond with peer.
#define NRF_DFU_BLE_REQUIRES_BONDS 1
```

编译工程，提示“#error NRF_DFU_BLE_REQUIRES_BONDS requires NRF_SDH_BLE_SERVICE_CHANGED. Please update the SoftDevice BLE stack configuration in sdk_config.h”。前面我们提到，Bonded DFU 过程中，DFU target 需要主动向DFU controller 发送service changed indication，让DFU controller 可以发现Bootloader 提供的DFU 服务，因此还需要启用NRF_SDH_BLE_SERVICE_CHANGED 如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\dfu\secure_bootloader\pca10040_s132_ble\config\sdk_config.h
//==========================================================
// <q> NRF_SDH_BLE_SERVICE_CHANGED  - Include the Service Changed characteristic in the Attribute Table.
#define NRF_SDH_BLE_SERVICE_CHANGED 1
```

重新编译工程，顺利完成，我们将生成的secure_bootloader_ble_s132_pca10040.hex 文件复制出来（也可以添加_bond 以区别与前面的unbond）。然后，在工程ble_app_buttonless_dfu_pca10040_s132 中启用NRF_DFU_BLE_BUTTONLESS_SUPPORTS_BONDS 如下：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_buttonless_dfu\pca10040\s132\config\sdk_config.h
// <h> ble_dfu - Device Firmware Update
//==========================================================
// <q> NRF_DFU_BLE_BUTTONLESS_SUPPORTS_BONDS  - Buttonless DFU supports bonds.
#define NRF_DFU_BLE_BUTTONLESS_SUPPORTS_BONDS 1
```

重新编译工程，顺利完成，我们将生成的ble_app_buttonless_dfu_pca10040_s132.hex 文件复制出来（也可以添加_bond 以区别与前面的unbond），执行前面介绍的生成Bootloader settings、合并烧录hex 文件的过程，nRF52 DK 系统正常启动，通过nRF Connect 连接“Nordic_Buttonless” 设备可以看到“Secure DFU Service” 服务。

我们将工程ble_app_buttonless_dfu_pca10040_s132 的DEVICE_NAME 改为“Nordic_DFU_V120”：

```c
// .\nRF5_SDK_17.0.2_d674dde\examples\ble_peripheral\ble_app_buttonless_dfu\main.c
#define DEVICE_NAME                     "Nordic_DFU_V120"                           /**< Name of device. Will be included in the advertising data. */
```

重新编译工程，将生成的hex 文件改为ble_app_buttonless_dfu_pca10040_s132_v120.hex，执行前面介绍的生成生成DFU package 过程，获得DFU 升级包SDK1702_app_s132_v120.zip，将其传到手机上用于DFU 升级。

手机端nRF Connect 执行DFU 的操作跟前面Unbonded BLE DFU 类似，主要区别是在进行DFU 之前需要先执行配对绑定操作，图示如下（点击“DFU” 图标选择DFU package 的过程跟前面完全一致，这里省略了）：
![nRF Connect for mobile Bonded BLE DFU procedure](https://img-blog.csdnimg.cn/20210416004626812.png?x-oss-process=image/watermark,type_ZmFuZ3poZW5naGVpdGk,shadow_10,text_aHR0cHM6Ly9ibG9nLmNzZG4ubmV0L20wXzM3NjIxMDc4,size_16,color_FFFFFF,t_70)

Bonded BLE DFU procedure 不再出现“DFUTARG” 设备了，这样印证了前面说到的，Bonded DFU 过程中DFU target 设备Application 和Bootloader 程序采用相同的蓝牙设备地址，配对绑定后DFU target 可以主动向DFU controller 发送service changed indication，让DFU controller 可以发现Bootloader 提供的DFU 服务，继续执行DFU 过程。

本工程源码下载地址：[https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/BLE_Buttonless_DFU](https://github.com/StreamAI/Nordic_nRF5_Project/tree/main/BLE_Buttonless_DFU)。


# 更多文章：

 - [《如何实现BLE 最大数据吞吐率并满足设计功耗要求？》](https://blog.csdn.net/m0_37621078/article/details/115483595)
 - [《如何抓包分析BLE 空口报文(GAP + GATT + LESC)？》](https://blog.csdn.net/m0_37621078/article/details/115181768)
 - [《如何实现扫码连接BLE 设备的功能?》](https://blog.csdn.net/m0_37621078/article/details/107193411)
 - [《Nordic_nRF5_Project》](https://github.com/StreamAI/Nordic_nRF5_Project)
 - [《Nordic nRF5 SDK documentation》](https://infocenter.nordicsemi.com/index.jsp?topic=/sdk_nrf5_v17.0.2/index.html)
 - [《BLE 技术（五）--- Generic Access Profile + Pairing and Bonding》](https://blog.csdn.net/m0_37621078/article/details/107850523)
 - [《BLE 技术（六）--- GATT Profile + Security Manager Protocol》](https://blog.csdn.net/m0_37621078/article/details/108391261)
 - [《Bluetooth Core Specification_v5.2》](https://www.bluetooth.com/specifications/bluetooth-core-specification/)