--- 模块功能：APP MAIN  
-- @author JWL
-- @license MIT
-- @copyright JWL
-- @release 2020.04.02

require"ril"
require "utils"
require "sys"
require "pm"
require "net"
require "record"
require "audio"
require "rtos"
require "misc"
require "common"
require "socket"
require "http"
require "pins"
require "nvm"
require "config"
require "gps"
require "agps"
require"wifiScan"

--require "ntp"
require "mutils"

module(..., package.seeall)


 




-- 串口ID,串口读缓冲区
local UARTD_ID =1
local UARTD_BAUD=115200
-- 串口超时，串口准备好后发布的消息
local uartimeout,RECV_MAXCNT = 100,1234
local CMDIN_Ready,CMDOUT_Ready="CMD_IN_ID","CMD_OUT_ID"
 

LBS_STATE=0
DEP_SLEEP=0
FACT_MODE=0
NOSIM_CNT=0

 
local PTARRAY={}



function NODEEP()
    if DEP_SLEEP == 0 and FACT_MODE == 0 then
        return true
    end
    return false
end

-- msk_engps:0 完全禁止， 1 完全打开，2 随系统 
-- msk_logps:0 关闭，1 LUATLOG, 2 OUTPC,3 双路
local msk_engps=2
local msk_logps=0
local netdis_tim=0

local flag_enatc=1
local flag_conned=false
local flag_initrun=true
local flag_usb=true
local max_gpsec,keep_gpsec=0,0
local str_upro = ""
local cmdrecvQ,cmdsendQ={},{}

local gps_power_ctrl = pins.setup(pio.P0_13, 0,  pio.PULLUP)
local led_ctrl = pins.setup(pio.P0_1,  0,  pio.PULLUP)
local green_ctrl= pins.setup(pio.P0_0, 0,  pio.PULLUP)

function led_set(onoff)
    pmd.ldoset( ( (onoff==1) and 13 or 0 ) ,pmd.LDO_VLCD)
    led_ctrl( (onoff==1) and 1 or 0 )
    log.info("led ",(onoff==1) and "on" or "off" )
end

led_keepblks=0
function led_blink()
    led_keepblks =  led_keepblks-1
    led_set( (led_keepblks %2 == 1) and 1 or 0 )
    if  led_keepblks <=0 then
          sys.timerStopAll(led_blink)
          led_set(0)
    end
end


local function push_cmd_out(cmdstr)
    table.insert(cmdsendQ,cmdstr)
    sys.timerStart(sys.publish, uartimeout, CMDOUT_Ready )
end


local function uartx_rsp(data)
    if flag_usb then
        uart.write(uart.USB, data) 
    else
        for i = 1, #data, 1460 do
            uart.write(UARTD_ID, data:sub(i, i + 1460 - 1))
        end
    end
end


uart.setup(UARTD_ID, UARTD_BAUD, 8, uart.PAR_NONE, uart.STOP_1)
uart.on(UARTD_ID, "receive", function(uid)
    local readstr= uart.read(uid, RECV_MAXCNT)
    log.info("uart1 recv_len =", #readstr)
    table.insert(cmdrecvQ, readstr)
    sys.timerStart(sys.publish, uartimeout, CMDIN_Ready )
    flag_usb=false
end)

--------------------------------------------------------------------
uart.setup(uart.USB, 0, 0, uart.PAR_NONE, uart.STOP_1)
uart.on(uart.USB, "receive", function()
    local readstr 
    while true do
        readstr= uart.read(uart.USB, RECV_MAXCNT)
        if #readstr >0 then
            flag_usb=true
            log.info("usb recv_len =", #readstr)
            table.insert(cmdrecvQ, readstr)
        else
            break
        end
    end
    sys.timerStart(sys.publish, uartimeout, CMDIN_Ready )
end)


sys.subscribe(CMDOUT_Ready, function()
    local sendstr = table.concat(cmdsendQ)
    cmdsendQ = {}
    uartx_rsp(sendstr) 
end)

sys.subscribe("GSENSOR_TEST", function(vibb,steps)
    push_cmd_out("+GSENSOR:"..vibb..","..steps.."\r\n") 
end)

local function check_wifi_info()
    wifiScan.request(function(result,cnt,tInfo)
        log.info("check_wifi_info.scanCb",result,cnt)
        if result then
            cxd_proto.wifiinfo =tInfo
        else
            cxd_proto.wifiinfo =nil
        end
    end)
end

 

function process_cmd(readstr)
    athead = string.match(readstr, "[aA][tT](%+*%w*)")
    if athead ~=nil then
        if athead =="" then
            push_cmd_out("\r\nOK\r\n")
        elseif string.match(readstr, "AT%+ENGPS=") ~= nil then
            readstr = string.trim(readstr)
            local gps_en = string.match( readstr, "ENGPS=(%d+)")
            gps_en = (gps_en ==nil or gps_en=="0") and 0 or tonumber(gps_en)

            msk_engps = gps_en
            if msk_engps ==1 then
                log.info("open_gps by usrcmd->","def")
                sys.publish("APPMSG_OPEN_GPS")
            elseif msk_engps ==0 then
                log.info("close_gps by usrcmd->","def")
                sys.publish("APPMSG_CLOSE_GPS")
            end
            push_cmd_out("\r\n+ENGPS:"..msk_engps.."\r\n")

        elseif string.match(readstr, "AT%+LOGPS=") ~= nil then     
            readstr = string.trim(readstr)
            local tmp_en = string.match( readstr, "LOGPS=(%d+)")
            tmp_en = (tmp_en ==nil or tmp_en=="0") and 0 or tonumber(tmp_en)
            msk_logps= tmp_en
            push_cmd_out("\r\n+LOGPS:"..msk_logps.."\r\n")

        elseif string.match(readstr, "AT%+HEART=") ~= nil then     
            readstr = string.trim(readstr)
            local tmp_ht = string.match( readstr, "HEART=(%d+)")
            tmp_ht = (tmp_ht ==nil or tmp_ht=="0") and 180 or tonumber(tmp_ht)
            nvm.set("heart_slot",tmp_ht )
            push_cmd_out("\r\n+HEART:"..tmp_ht.."\r\n")
        elseif string.match(readstr, "AT%+CYCLE=") ~= nil then     
            readstr = string.trim(readstr)
            local tmp_cy = string.match( readstr, "CYCLE=(%d+)")
            tmp_cy = (tmp_cy ==nil or tmp_cy=="0") and 1800 or tonumber(tmp_cy)
            nvm.set("cycle_slot",tmp_cy )
            push_cmd_out("\r\n+CYCLE:"..tmp_cy.."\r\n")

        elseif string.match(readstr, "AT%+QRWIFI") ~= nil then     
            push_cmd_out("\r\n+QRWIFI:CHECKING\r\n")
            wifiScan.request(function(result,cnt,tInfo)
           
                log.info("check_wifi_info.scanCb",result,cnt)
                if result then
                    local wifiinfo =tInfo
                    
                    if wifiinfo ~=nill then
                        local strwifis=""
                        local cnt=0
                        for k,v in pairs(wifiinfo) do
                            cnt=cnt+1
                            log.info("testWifi.scanCb",k:upper(),v)
                            if strwifis ~="" then strwifis = strwifis.."|"  end
                            strwifis=strwifis..string.format("AP%02d",cnt).."#"..k:upper().."#"..v
                        end
                        push_cmd_out("\r\n+QRWIFI:" ..tostring(cnt).."," .. strwifis ..  "\r\n")
                    end
                else
                    push_cmd_out("\r\n+QRWIFI:0\r\n")
                end
            end)


        elseif string.match(readstr, "AT%+QRLBS") ~= nil then     
            local cellinfo = net.getCellList()
            local strcells = ""
            if cellinfo ~=nil then
                local cnt=0
                for i=1,#cellinfo do
                   if cellinfo[i].lac ~=0 and cellinfo[i].ci~=0 then
                       if strcells ~="" then strcells = strcells.."|"  end
                       strcells=strcells.. cellinfo[i].lac.."#".. cellinfo[i].ci.."#"..tostring(cellinfo[i].rssi*2-113)
                       cnt=cnt+1
                   end
                end
                if strcells ~="" then
                    push_cmd_out("\r\n+QRLBS:" ..tostring(cnt).."," .. strcells ..  "\r\n")
                else
                    push_cmd_out("\r\n+QRLBS:0\r\n")
                end
            end
            
        elseif  string.match(readstr, "AT%+RIL=") ~= nil then
            local temp_enatc = string.match(readstr, "+RIL=(%d+)")
            flag_enatc = (temp_enatc==nil or temp_enatc =="0") and 0 or 1
            if flag_enatc == 0 then  ril.setrilcb(nil) end
            push_cmd_out("\r\n+RIL:"..flag_enatc.."\r\n")

        elseif  string.match(readstr, "AT%+LOGLVL=") ~= nil then
            local tmp_lvl = string.match(readstr, "+LOGLVL=(%d+)")
            if tmp_lvl ~=nil then
                tmp_lvl = tonumber(tmp_lvl)
            end
            log.set_loglvl(tmp_lvl)
            push_cmd_out("\r\n+LOGLVL:"..tmp_lvl.."\r\n")

        elseif  string.match(readstr, "AT%+SLEEP") ~= nil then
            cxd_proto.cxd_sleep_req()
            push_cmd_out("\r\n+SLEEP:OK\r\n")

        elseif  string.match(readstr, "AT%+LOGTRACE") ~= nil then
            rtos.set_trace(1, 4)--USB TRACE
            push_cmd_out("\r\n+LOGTRACE:OK\r\n")
         
        elseif  string.match(readstr, "AT%+CGMR") ~= nil then
            push_cmd_out('+CGMR:"'.. _G.PROJECT.."_".._G.VERSION.."_"..rtos.get_version()..'"\r\n\r\nOK')

        elseif  string.match(readstr, "AT%+RESTORE") ~= nil then
            push_cmd_out("\r\n+RESTORE:OK\r\n")
            sys.timerStart(function() 
                nvm.restore()
                sys.restart("CXD_S10")
            end, 1000)

        elseif  string.match(readstr, "AT%+POWEROFF") ~= nil then
            push_cmd_out("\r\n+POWEROFF:OK\r\n")
            sys.timerStart(function() 
                rtos.poweroff()
            end, 200)
        elseif  string.match(readstr, "AT%+SERV=") ~= nil then
            readstr = string.trim(readstr)
            local tmpip, tmpport = string.match(readstr, "SERV=(.+),(.+)")
            if tmpip ~=nil and tmpport ~=nil and  tmpip ~="" and tmpport ~="" then
                local flag_changed =false
                if nvm.get("serv_ipadd") ~= tmpip then
                    nvm.set("serv_ipadd",tmpip )
                    flag_changed=true
                end
                if nvm.get("serv_port") ~= tmpport then
                    nvm.set("serv_port" ,tmpport)
                    flag_changed=true
                end
                if flag_changed then
                        sys.publish("T_SOCKET_SEND_DATA","CLIENT_EXIT")
                end
                push_cmd_out("\r\n+SERV:"..tmpip..","..tmpport.."\r\n".. "OK\r\n")
            else
                push_cmd_out("\r\n+SERV:"..tmpip..","..tmpport.."\r\n".. "FAIL\r\n")
            end
        elseif  string.match(readstr, "AT%+APN=") ~= nil then
            readstr = string.trim(readstr)
            local tmpapn, tmpuser,tmppassword = string.match(readstr, "APN=(.+),(.+),(.+)")
            if tmpapn ~=nil and tmpuser ~=nil and tmppassword ~=nil then
                local flag_changed =false

                if nvm.get("apn") ~= tmpapn then
                    nvm.set("apn",tmpapn )
                    flag_changed=true
                end
                if nvm.get("username") ~= tmpuser then
                    nvm.set("username" ,tmpuser)
                    flag_changed=true
                end
                if nvm.get("password") ~= tmppassword then
                    nvm.set("password" ,tmppassword)
                    flag_changed=true
                end

                push_cmd_out("\r\n+APN:"..tmpip..","..tmpport..","..tmpport.."\r\n".. "OK\r\n")
            else
                push_cmd_out("\r\n+APN:".. "FAIL\r\n")
            end
        elseif  string.match(readstr, "AT%+GETCFG?") ~= nil then
            local cfgobj={HOST=nvm.get("host"),
                cycle_slot=nvm.get("cycle_slot"),
                heart_slot=nvm.get("heart_slot"),
                serv_ipadd=nvm.get("serv_ipadd"),
                serv_port=nvm.get("serv_port"),
                plmn=nvm.get("plmn"),  
                apn=nvm.get("apn"), 
                username=nvm.get("username"), 
                password=nvm.get("password"),
                DEP_SLEEP=app_main.DEP_SLEEP,
                FLY_MODE = net.flyMode,
                voltage  = battery.getVRbattEx(),
            }
            push_cmd_out( "\r\n+GETCFG:"..json.encode(cfgobj).."\r\n")


        elseif  string.match(readstr, "AT%+STEP?") ~= nil then
            push_cmd_out( "\r\n+STEP:"..gsensor.mir3da_get_step().."\r\n")
        elseif  string.match(readstr, "AT%+GPSINFO") ~= nil then
            log.info(" gps.getLocation(), ", json.encode(gps.getLocation()))
            log.info(" gps.getAltitude(), ", gps.getAltitude())
            log.info(" gps.getSpeed(), ", gps.getSpeed())
            log.info(" gps.getOrgSpeed(), ", gps.getOrgSpeed())
            log.info(" gps.getCourse(), ", gps.getCourse())
            log.info(" gps.getMaxSignalStrength(), ", gps.getMaxSignalStrength())
            log.info(" gps.getViewedSateCnt(), ", gps.getViewedSateCnt())
            log.info(" gps.getUsedSateCnt(), ", gps.getUsedSateCnt())
            log.info(" gps.getGgaloc(), ", gps.getGgaloc())
            log.info(" gps.getUtcTime(), ", json.encode(gps.getUtcTime()))
            log.info(" gps.getSep(), ", gps.getSep())
            log.info(" gps.getSateSn(), ", gps.getSateSn())
            log.info(" gps.getGsv(), ", gps.getGsv())
            log.info(" link.getAPN(), ", link.getAPN())

        elseif  string.match(readstr, "AT%+BATTERY") ~= nil then
            push_cmd_out( "\r\n+BATTERY:"..misc.getVbatt()..","..battery.getCapacity().."% USBIN="..tostring(battery.isUSBConnected()).."\r\n")
            
        elseif  string.match(readstr, "AT%+TESTMODE") ~= nil then
            app_main.FACT_MODE =1
            sys.timerStopAll(tmr_close_gps)
            sys.publish("T_SOCKET_SEND_DATA","CLIENT_EXIT")
            push_cmd_out( "OK,Please wait..\r\n")

            sys.timerStart( function() 
                msk_engps=1
                if not gps.isActive(gps.DEFAULT,{tag="DEFAULT"})  then   
                    gps.open(gps.DEFAULT,{tag="DEFAULT"}) 
                end
                push_cmd_out( "\r\n==========NOW IS TESTING MODE============\r\n")
            end, 2000)

        elseif  string.match(readstr, "AT%+GPSCMD=") ~= nil then
            readstr = string.trim(readstr)
            local isFull,str_cmd = string.match(readstr, "GPSCMD=(%d+),(.+)")
            if isFull ~=nil and str_cmd ~=nil then
                str_cmd = string.trim(str_cmd)
                gps.writeCmd(str_cmd, (isFull ==1) )
            else
                push_cmd_out("\r\n+GPSCMD:".. "FAIL\r\n")
            end
        else
            --common atcmd process
            if  flag_enatc == 1 then
                ril.setrilcb(push_cmd_out)
                ril.request(readstr)
            end
        end
   end
 
end


sys.subscribe(CMDIN_Ready, function()
    local readstr = table.concat(cmdrecvQ)
    cmdrecvQ = {}
    process_cmd(readstr)
end)





gps.setPowerCbFnc(
    function(status)
        gps_power_ctrl(status and 1 or 0)    
        pmd.sleep(status and 0 or 1) 
        log.info("sleep mode:", status and 0 or 1)
    end
)
gps.setUart(3, 9600, 8, uart.PAR_NONE, uart.STOP_1)
gps.setParseItem(true)

--内部处理数据，用户打印nmea信息
local function nmeaCb(nmeaItem)
    if msk_logps ==1 or msk_logps == 3 then
         log.info("testGps.nmeaCb", nmeaItem)
    end
    if msk_logps ==2 or msk_logps == 3 then
        uartx_rsp(nmeaItem)
    end
end

gps.setNmeaMode(2, nmeaCb)


function gps_rdy()
    return gps.isFix()
end


local EARTH_RADIUS = 6378.137 --地球周长
--GPS距离算法
--功能：计算两点之间距离
--参数：度格式的两个坐标，先经度后纬度
--返回值：两点之间距离，单位米，可以修改最后的返回值修改为千米
local function getDistance(lat1, lng1, lat2, lng2)

    local rad1 = math.rad(lat1)
    local rad2 = math.rad(lat2)
    local rada = rad1 - rad2
    local radl = math.rad(lng1) - math.rad(lng2)
    local s =
        2 *
        math.asin(
            math.sqrt(
                math.pow(math.sin(rada / 2), 2) + math.cos(rad1) * math.cos(rad2) * math.pow(math.sin(radl / 2), 2)
            )
        )
    s = s * EARTH_RADIUS
    return s * 1000 -- 单位米
end

gps.setEnGPSPoint(true)


local function reset_lbstate()
    LBS_STATE =0
    if msk_engps ~= 1  then  
        log.info("------------reset_lbstate-----------")
        sys.publish("APPMSG_CLOSE_GPS")
    end
end

local function tmr_open_gps(tpslot)
    log.info("open_gps by timer->",tpslot,"gps.isFix()=",gps.isFix())
    sys.publish("APPMSG_OPEN_GPS",tpslot)
end
local function tmr_close_gps()
    max_gpsec,keep_gpsec = 0,0
    gps.close(gps.DEFAULT, {tag = "DEFAULT"})
end


function ENTER_SLEEP_MODE()
    sys.taskInit(function()
        cxd_proto.cxd_sleep_req()
        sys.wait(3000)
        log.info("jwill---------ENTER_SLEEP_MODE------")
        DEP_SLEEP=1
        sys.publish("T_SOCKET_SEND_DATA","CLIENT_EXIT")

        if msk_engps ~= 1  then  
            sys.publish("APPMSG_CLOSE_GPS")
        end
        sys.wait(3000)
        net.switchFly(true)
    end)
end

local  function delay50s_report_gps()
    log.info("retry_gps cxd_proto.cxd_upgps_req(C4)", max_gpsec,keep_gpsec )  
    cxd_proto.cxd_upgps_req("C4") 
end




function ENTER_WORK_MODE(reason)

    gsensor.silen_cnt = 0
    net.switchFly(false)
    flag_initrun=true

    if msk_engps >0 then
        log.info("open_gps by initrun->",300)
        sys.publish("APPMSG_OPEN_GPS",300)
    end

    if  DEP_SLEEP==1 then
        DEP_SLEEP =0
    end

    log.info("jwill---------ENTER_WORK_MODE------",reason)

    sys.taskInit(function()
        local retry_cnn=0
        local r, s, p
        local tip, tport ="",0
        log.info("jwill enter socket task+++++++++++++++")

        while NODEEP() do
            local count = 0
            while  not socket.isReady() do--等联网
                count = count + 1
                log.info("check net",count)
                sys.wait(1000)

                if count > 60 then
                    net.switchFly(true)
              
                    --60S都注册不上网络，说明开GPS 也没意义。
                    if gps.isOpen() then 
                        sys.publish("APPMSG_CLOSE_GPS")
                    end
                    local ht_cnt =  nvm.get("heart_slot")
                    if ht_cnt<30 then ht_cnt =30 end
                    log.info("jwill no network ,so will goto longtime flymode",ht_cnt)

                    while NODEEP() do
                        sys.wait(1000)
                        if ht_cnt >0 then
                            ht_cnt = ht_cnt -1
                        else
                            if sim.getStatus() then
                                ril.request("AT+CPIN?")  
                            else
                                -- 防止卡松了，重启试试。
                                NOSIM_CNT = NOSIM_CNT +1 
                                if NOSIM_CNT >=2 then 
                                    log.info("jwill reset for check simcard")
                                    sys.timerStart(function() 
                                         sys.restart("RECHECK SIM")
                                    end,1000)
                                end
                            end
                            
                            break;
                        end
                    end

                    net.switchFly(false)
                    count = 0
                end
            end
            ril.request("AT+WAKETIM=1\r\n")
            sys.timerStart(function() 
                ril.request("AT*RTIME=2\r\n")
            end,1000)

            --GPS如果之前没有打开(多半是因为没有网络信号)，就确保性的打开一次
            if not gps.isActive(gps.DEFAULT,{tag="DEFAULT"})  then   
                gps.open(gps.DEFAULT,{tag="DEFAULT"}) 
            end
        
            while NODEEP() do
                tip = nvm.get("serv_ipadd")
                tport =nvm.get("serv_port")

                if tip~=nil and tport ~=nil and   #tip >0  then 
                    tport =tonumber(tport)
                    break
                else
                    log.info("err serv ip & port", tip, tport)
                    sys.wait(2000)
                end
            end
            log.info("+++++++++++++++ socket ready+++++++++++++++")

            local c = socket.tcp()
            if c:connect(tip, tport) then
                flag_conned=true
                retry_cnn=0
                
                while NODEEP() do
                    local ht_slot =  nvm.get("heart_slot")
                    ht_slot = (ht_slot==nil or ht_slot ==0) and (180 *1000) or (ht_slot *1000)
                    local r, s, p = c:recv(ht_slot, "T_SOCKET_SEND_DATA")
                    if r then
                        if  s and  #s >0 then
                            log.info("socket recv <-----", s)
                            str_upro = str_upro..s
                            while NODEEP() do
                                str_upro =cxd_proto.cxd_any_cmd(str_upro)
                                if #str_upro >0 then
                                    log.info("unprocessed data ***", str_upro)
                                    if not cxd_proto.cxd_chk_cmd(str_upro) then
                                        sys.timerStart(function() 
                                            str_upro =""
                                        end,2000)
                                        break
                                    end
                                else
                                    break
                                end
                            end
                        end
                    elseif s == "T_SOCKET_SEND_DATA" then
                        if p =="CLIENT_EXIT" or FLAG_GOO_EXIT ==1 then 
                            log.info("CLIENT_EXIT  by myself----------------")
                            break 
                        else
                            log.info("socket send----->", p)
                            if not c:send(p,10) then break end
                        end
                    elseif s == "timeout" then
                        if cxd_proto.glogin then
                        cxd_proto.cxd_heart_req()
                        end
                    else
                        log.info("loop exit r,s,p",r,s,p)
                        break
                    end
                end
            else
                retry_cnn = retry_cnn +1
                if retry_cnn >3 then
                    retry_cnn =0
                    log.info("RETRY CONNNECTE TIME MORE THAN 3----------------")
                    link.shut()
                    net.switchFly(true)
                    sys.wait(2000)
                    net.switchFly(false)

                    if  NODEEP() then
                        sys.wait(2000)
                    end
                end
            end
            flag_conned=false
            r,s,p = nil,nil,nil
            c:close()
        end

        log.info("jwill exit socket task---------------")
    end)



    ----基本业务工作任务
    sys.taskInit(function()
        log.info("jwill enter basic task+++++++++++++++")
        local ori_slot=0
        while NODEEP() do
            if  socket.isReady() and flag_conned  then
                netdis_tim = 0
                if LBS_STATE ==0 then
                    cxd_proto.cxd_login_req()
                    
                    LBS_STATE=1
                elseif LBS_STATE ==1 then
                    if not sys.timerIsActive(reset_lbstate)  then 
                        sys.timerStart( reset_lbstate,  10000)
                    else
                        if cxd_proto.glogin then
                            sys.timerStopAll(reset_lbstate)

                            if not gps.isOpen() then
                                log.info("open_gps by login",300)
                                sys.publish("APPMSG_OPEN_GPS",300)
                            end

                            LBS_STATE =2
                        end
                    end
                --周期性上报(开机最长会开5分钟的GPS 确保搜星)
                elseif LBS_STATE ==2 then
                    if flag_initrun then
                        flag_initrun =false
                        log.info("first_gps cxd_proto.cxd_upgps_req(C4)" )    
                        cxd_proto.cxd_upgps_req("C4")
                        if not gps.isFix() then
                            sys.timerStart( delay50s_report_gps, 50 *1000)
                        else
                            if msk_engps ~= 1  then  
                                log.info("close_gps by first succeed->")
                                sys.publish("APPMSG_CLOSE_GPS")
                            end
                        end
                    else
                        local cl_slot =  nvm.get("cycle_slot")
                        if cxd_proto.track_slot >0 then cl_slot = cxd_proto.track_slot end

                        if cxd_proto.gtr_changed then 
                            cxd_proto.gtr_changed =false
                            --云智星平在跟踪模式下，会多次下发S6,如果是短时间之内的，就不要关闭GPS
                            if cl_slot >30 then
                                if msk_engps ~= 1  then  
                                    sys.timerStopAll(tmr_close_gps)
                                    log.info("close_gps by gtr_changed->",cl_slot)
                                    sys.publish("APPMSG_CLOSE_GPS")
                                end
                            end

                            if ori_slot ~= cl_slot then
                                ori_slot = cl_slot
                                sys.timerStopAll(tmr_open_gps)
                            end
                        end

                        if gps.isOnece() then 
                            local tmpslot = cl_slot>50 and 50 or cl_slot
                            if not sys.timerIsActive(tmr_open_gps, tmpslot)  then 
                                log.info("will start new tmr_open_gps",tmpslot)
                                sys.timerStart( tmr_open_gps, cl_slot *1000, tmpslot)
                            end
                        else
                            if keep_gpsec ==0 then 
                                if not sys.timerIsActive(tmr_open_gps)  then 
                                    cur_slot = (cl_slot>GPSOP_KEEPS) and GPSOP_KEEPS or cl_slot
                                    log.info("will start new tmr_open_gps2",cur_slot)
                                    sys.timerStart( tmr_open_gps, cl_slot *1000)
                                end
                            end
                        end

                        if keep_gpsec >0 then
                            log.info("fffffffind_gps  max_gpsec, keep_gpsec->", max_gpsec,keep_gpsec )       
                            keep_gpsec = keep_gpsec-1

                            if gps.isFix() or keep_gpsec ==0 then 
                                keep_gpsec =0
                                cxd_proto.cxd_upgps_req( max_gpsec >20 and "C4" or "C18")
                                --40S通过GPS获取了GPS 信号，所以不用延迟上报
                                sys.timerStopAll(delay50s_report_gps)

                                if msk_engps ~= 1 and  max_gpsec >=30 then  
                                    sys.timerStopAll(tmr_close_gps)
                                    log.info("close_gps by keep_gpsec->", max_gpsec >20 and "C4" or "C18")
                                    sys.publish("APPMSG_CLOSE_GPS")
                                else
                                    check_wifi_info()
                                end
                            end
                        end  
                    end             
                end
                sys.wait(1000)
            else
                LBS_STATE=0
                sys.wait(5000)

                netdis_tim = netdis_tim +1 
                if netdis_tim > 30 then
                    log.info("no network so long ==>",netdis_tim *5 ) 
                    netdis_tim = 0
                    if gps.isOpen() then
                        tmr_close_gps()
                    end
                end
            end
        end
        log.info("jwill exit basic task------------")        
    end)

end


--尝试进入工作模式，主要是防止充不进电,或者模块跑不起来。

function TRYING_WORK_MODE(reason)
    sys.taskInit(function() 
        net.switchFly(true)
        sys.wait(2000)

        while true do 
            local vtot =0
            for i=1,5 do
                vtot = vtot + battery.getVRbattEx()
                sys.wait(400)
            end
            local cur_volt= math.floor( vtot /5)

            log.info(" battery voltage=", cur_volt )


            if cur_volt > 3500 then
                log.info("jwill TRYING_WORK_MODE+++++++++++vbat++++", cur_volt )
                break
            elseif cur_volt <3450 then    --低于3.45V 就配置10分钟起来一次
                
                -- log.set_loglvl(1)
  
                -- sys.wait(200)

          
                -- log.info("volt ,alarm restart time", cur_volt, (60 * 10))

                -- local onTimet = os.date("*t",os.time() + (60 * 10))  --下次要开机的时间为60 * 10秒后
                -- rtos.set_alarm(1,onTimet.year,onTimet.month,onTimet.day,onTimet.hour,onTimet.min,onTimet.sec)   --设定闹钟时间
                -- sys.wait(1000)
                -- rtos.poweroff()
     
            end
        end
        ----------- 只有大于3.55V才能运作起来
        ENTER_WORK_MODE(reason)
    end)
end


---用于控制GPS
-- 一米阳光:
-- 如果是平台下发的秒定功能：最长打开时间30S；
-- 默认的180S的间隔的定位周期：GPS最长打开时间50S。


sys.subscribe("APPMSG_OPEN_GPS", function(max_sec)
  
    if max_sec ==nil then max_sec =50 end
    max_gpsec,keep_gpsec = max_sec,max_sec
    if keep_gpsec >0 then
        if not gps.isActive(gps.DEFAULT,{tag="DEFAULT"})  then   
                   gps.open(gps.DEFAULT,{tag="DEFAULT"}) 
        end

        check_wifi_info()

        --只有间隔超过30S 才有休眠的意义，否则GPS 唤醒后搜星也可能要几十秒。
        if msk_engps ~= 1 and  max_gpsec >=30 then  
            PTARRAY={}
            sys.timerStart(tmr_close_gps, max_gpsec *1000)
        end
    end
end)

sys.subscribe("APPMSG_CLOSE_GPS", function()
    PTARRAY={}
    tmr_close_gps()
end)




led_keepblks = 6*2 +1
sys.timerLoopStart(led_blink,500)




local sta,longprd,longcb,shortcb = "IDLE",2500

local function longtimercb()
    log.info("keypad.longtimercb")
    sta = "LONGPRESSED"	
    pmd.ldoset(13 ,pmd.LDO_VLCD)
    led_ctrl(1)
    sys.timerStart( rtos.poweroff , 3000)
end

local function keyMsg(msg)
    log.info("keyMsg",msg.key_matrix_row,msg.key_matrix_col,msg.pressed)
    if msg.pressed then
        sta = "PRESSED"
        sys.timerStart(longtimercb,longprd)
    else
        sys.timerStop(longtimercb)
        if sta=="PRESSED" then
            if not NODEEP() then
                TRYING_WORK_MODE("pwr key")
            end
        elseif sta=="LONGPRESSED" then
   
		end
		sta = "IDLE"
	end
end
rtos.on(rtos.MSG_KEYPAD,keyMsg)
rtos.init_module(rtos.MOD_KEYPAD,0,0,0)


sys.timerStart(function() 
    TRYING_WORK_MODE("first start")
end,1000)

