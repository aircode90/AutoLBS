--- 模块功能：充电管理.
-- @author openLuat
require"misc"
module(...,package.seeall)

local flag_usbin = false
local flag_charging = false

function isUSBConnected()
    return flag_usbin
end

function isChargerIn()
    return flag_charging
end

local vlist={}

local VPL=10
table.insert(vlist,{4160 -VPL *4,100})
table.insert(vlist,{4080 -VPL *4,95})
table.insert(vlist,{4000 -VPL *4,90})
table.insert(vlist,{3945 -VPL *3,85})
table.insert(vlist,{3890 -VPL *3,80})
table.insert(vlist,{3836 -VPL *3,75})
table.insert(vlist,{3797 -VPL *3,70})
table.insert(vlist,{3763 -VPL *2,65})
table.insert(vlist,{3730 -VPL *2,60})
table.insert(vlist,{3695 -VPL *2,55})
table.insert(vlist,{3660 -VPL *2,50})
table.insert(vlist,{3644 -VPL *2,45})
table.insert(vlist,{3629 -VPL,40})
table.insert(vlist,{3610 -VPL,35})
table.insert(vlist,{3592 -VPL,30})
table.insert(vlist,{3573 -VPL,25})
table.insert(vlist,{3555 -VPL,20})
table.insert(vlist,{3516 -VPL,15})
table.insert(vlist,{3478 -VPL,10})
table.insert(vlist,{3439 -VPL,5})
 
--获取剩余电量，单位百分比，例如70%，则此函数返回70
function getCapacity()
    local vbat = misc.getVbatt()
    local capacity

    local upele,dwele=nil,nil
    for i=1,#vlist do
        upele,dwele=nil,nil
        if vbat >= vlist[i][1] then
            if i >1 then   upele = vlist[i-1]  end
            dwele = vlist[i]
            break
        end
    end

    local elem_typ=""
    if upele ==nil and dwele == nil then 
        elem_typ = "elem low"
        capacity =1
    elseif upele == nil then
        capacity=100
        elem_typ = "elem high"
    else
        local range = upele[1] - dwele[1]
        local delta = vbat     - dwele[1]
        capacity =  math.floor(  dwele[2] + (delta * 5/range ))
        elem_typ = "elem midd"
      --  log.info("-------------------------------elem range",dwele[1],"~",upele[1] ,"   ", dwele[2],"~",upele[2]    )
    end
    if  flag_charging  then
       log.info("++++++++++++++++++++++++++++++++elem capacity, vbat",elem_typ, capacity, vbat)
    end

    return  math.floor( capacity )
end


function getVRbattEx()
    local vbat      = misc.getVbatt()
    local adcval,voltval = adc.read(5)
    log.info("testAdc5.read,   adcval,voltval , vbat ",adcval,voltval, vbat)
    ---居然有读到65535的！！！插拔USB
    if voltval <5000 and voltval >2000 then
        ram_adc = voltval
    elseif ram_adc == 0  then
        ram_adc = vbat
    end
    return ram_adc
end

local function disable_rndis()
    ril.request("AT+RNDISCALL=1,1")
    sys.timerStart(function() 
       ril.request("AT+RNDISCALL=0,1")
    end, 1000)
end
 
local function proc(msg)
    if msg then 
        local flag_chned=false
        if flag_charging ~= msg.charger then
             flag_charging = msg.charger
             flag_chned=true
        end

        local tmp_usbin=false
        if msg.state ==0 then
            tmp_usbin = false
        else
            tmp_usbin = true
            sys.timerStart(disable_rndis, 8000)
        end

        if  flag_usbin ~= tmp_usbin then
            flag_usbin = tmp_usbin
            flag_chned =true

            if flag_usbin then
    
                if not app_main.NODEEP() then
                    if battery.getVRbattEx() >3500  then
                        app_main.TRYING_WORK_MODE("usb connected a")
                    end
                end
            else
                log.info("---clear gsensor.silen_cnt to 0 ---")
                gsensor.silen_cnt = 0
                app_main.led_set(0)
            end
        end

        log.info("usb present, level, voltage, charger, state", msg.present, msg.level, msg.voltage, msg.charger, msg.state )
   
    end
end
rtos.on(rtos.MSG_PMD,proc)
pmd.init({}) 




local bat_keepblks=0
local function bat_blink()
    bat_keepblks =  bat_keepblks-1
    app_main.led_set( (bat_keepblks %2 == 1) and 1 or 0 )
    if  bat_keepblks <=0 then
          sys.timerStopAll(bat_blink)
          app_main.led_set(0)
    end
end

local function lowbat_5min()
    if not flag_usbin and  getCapacity() <20  then
        bat_keepblks=4*2 +1
        sys.timerLoopStart(bat_blink,300)
    end
end

sys.taskInit(function()
   --leds charging,low power tec
    while true do
        if app_main.FACT_MODE == 0 then
            if app_main.led_keepblks ==0 then 
                if flag_usbin then
                    if  flag_charging and  getCapacity() <100 then
                        bat_keepblks=1*2 +1
                        sys.timerLoopStart(bat_blink,300)
                    else
                        app_main.led_set(1)
                    end
                else
                    if getCapacity() <20 then
                    if not sys.timerIsActive(lowbat_5min) then
                        sys.timerStart(lowbat_5min, 300 * 1000)
                        log.info("led lowbat_5min start");

                        if app_main.DEP_SLEEP ==1 then 
                                app_main.TRYING_WORK_MODE("capacity <20%")
                        end
                    end
                    end
                end    
            end
        end
        sys.wait(3000)
    end
end)

 
