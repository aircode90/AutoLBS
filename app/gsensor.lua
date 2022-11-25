-- Air724读取gsensor da217
-- BY JWL 2020-12-19

module(..., package.seeall)

require "pins"

local NSA_REG_SPI_I2C      =          0x00 
local NSA_REG_WHO_AM_I     =          0x01 
local NSA_REG_ACC_X_LSB    =          0x02 
local NSA_REG_ACC_X_MSB    =          0x03 
local NSA_REG_ACC_Y_LSB    =          0x04 
local NSA_REG_ACC_Y_MSB    =          0x05 
local NSA_REG_ACC_Z_LSB    =          0x06 
local NSA_REG_ACC_Z_MSB    =          0x07 
local NSA_REG_MOTION_FLAG	 =	      0x09  
local NSA_REG_STEPS_MSB	   =          0x0D         
local NSA_REG_STEPS_LSB		 =	      0x0E         
local NSA_REG_G_RANGE      =          0x0F 
local NSA_REG_ODR_AXIS_DISABLE  =     0x10 
local NSA_REG_POWERMODE_BW      =     0x11 
local NSA_REG_SWAP_POLARITY     =     0x12 
local NSA_REG_FIFO_CTRL         =     0x14 
local NAS_REG_INT_SET0			   =  0x15         
local NSA_REG_INTERRUPT_SETTINGS1  =  0x16 
local NSA_REG_INTERRUPT_SETTINGS2  =  0x17 
local NSA_REG_INTERRUPT_MAPPING1   =  0x19 
local NSA_REG_INTERRUPT_MAPPING2   =  0x1a 
local NSA_REG_INTERRUPT_MAPPING3   =  0x1b 
local NSA_REG_INT_PIN_CONFIG       =  0x20 
local NSA_REG_INT_LATCH            =  0x21 
local NSA_REG_ACTIVE_DURATION      =  0x27 
local NSA_REG_ACTIVE_THRESHOLD     =  0x28 
local NSA_REG_TAP_DURATION         =  0x2A 
local NSA_REG_TAP_THRESHOLD        =  0x2B 
local NSA_REG_STEP_CONFIG1		   =  0x2F       
local NSA_REG_STEP_CONFIG2		   =  0x30       
local NSA_REG_STEP_CONFIG3		   =  0x31       
local NSA_REG_STEP_CONFIG4		   =  0x32       
local NSA_REG_STEP_FILTER		   =  0x33       
local NSA_REG_SM_THRESHOLD		   =  0x34       
local NSA_REG_CUSTOM_OFFSET_X      =  0x38 
local NSA_REG_CUSTOM_OFFSET_Y      =  0x39 
local NSA_REG_CUSTOM_OFFSET_Z      =  0x3a 
local NSA_REG_ENGINEERING_MODE     =  0x7f 
local NSA_REG_SENSITIVITY_TRIM_X   =  0x80 
local NSA_REG_SENSITIVITY_TRIM_Y   =  0x81 
local NSA_REG_SENSITIVITY_TRIM_Z   =  0x82 
local NSA_REG_COARSE_OFFSET_TRIM_X =  0x83 
local NSA_REG_COARSE_OFFSET_TRIM_Y =  0x84 
local NSA_REG_COARSE_OFFSET_TRIM_Z =  0x85 
local NSA_REG_FINE_OFFSET_TRIM_X   =  0x86 
local NSA_REG_FINE_OFFSET_TRIM_Y   =  0x87 
local NSA_REG_FINE_OFFSET_TRIM_Z   =  0x88 
local NSA_REG_SENS_COMP            =  0x8c 
local NSA_REG_MEMS_OPTION          =  0x8f 
local NSA_REG_CHIP_INFO            =  0xc0 
local NSA_REG_CHIP_INFO_SECOND     =  0xc1 
local NSA_REG_MEMS_OPTION_SECOND   =  0xc7 
local NSA_REG_SENS_COARSE_TRIM     =  0xd1 
local NAS_REG_OSC_TRIM			   =  0x8e         






local i2c_id = 2      -- I2C id号
local i2c_addr = 0x26 -- i2c地址
local vibb_cnt=0
local fina_rpt=0



local function mir3da_register_write(regaddr,data)
   return i2c.send(i2c_id, i2c_addr, {regaddr,data})
end

local function mir3da_register_read(regaddr,rdlen)
    i2c.send(i2c_id, i2c_addr, regaddr)
    return  i2c.recv(i2c_id, i2c_addr, rdlen)
end
 

local function mir3da_register_mask_write(addr,mask,data)
  
     local tmp_recv = mir3da_register_read(addr, 1);
     if tmp_recv ~=nil then
        return #tmp_recv
     end
     local tmpmsk = bit.bnot(mask)
 
     local tmpdat = bit.band(0, tmpmsk)
     local mskdat = bit.band(data, mask)
     tmpdat = bit.bor(mskdat, tmpdat)

     return mir3da_register_write(addr, string.byte(tmpdat));
end

local function mir3da_init()
    local cnt =0
    while cnt <3 do
        cnt =cnt +1
        local res= mir3da_register_read(NSA_REG_WHO_AM_I,1)
        if #res >0 then
             if string.byte(string.sub(res,1,1)) == 0x13 then
                  break
             end
        end
    end

    if cnt >=3 then
        return 
    end

    mir3da_register_mask_write(0x00, 0x24, 0x24);

	 mir3da_register_write(NSA_REG_G_RANGE, 0x01);            
     mir3da_register_write(NSA_REG_POWERMODE_BW, 0x14);        
	 mir3da_register_write(NSA_REG_ODR_AXIS_DISABLE, 0x07);      --------------
	 mir3da_register_write(NSA_REG_ENGINEERING_MODE, 0x83);
	 mir3da_register_write(NSA_REG_ENGINEERING_MODE, 0x69);
	 mir3da_register_write(NSA_REG_ENGINEERING_MODE, 0xBD);
     mir3da_register_write(NSA_REG_INT_PIN_CONFIG, 0x00);  
     
     if i2c_addr == 0x26 then
		mir3da_register_mask_write(NSA_REG_SENS_COMP, 0x40, 0x00);
	 end

end


local function mir3da_open_interrupt(th) 
    mir3da_register_write(NSA_REG_ACTIVE_DURATION,0x02);
    mir3da_register_write(NSA_REG_ACTIVE_THRESHOLD,th);
    mir3da_register_write(NSA_REG_INTERRUPT_MAPPING1,0x04);
   -- mir3da_register_write(NSA_REG_INT_LATCH, 0x0C);  --latch ms
    mir3da_register_write(NSA_REG_INT_LATCH, 0x04);  --latch 04=2S  ,05=4S
    mir3da_register_write(NSA_REG_INTERRUPT_SETTINGS1,0x87);
end





local function mir3da_open_step_counter()
    mir3da_register_write(NSA_REG_STEP_CONFIG1, 0x01);
    mir3da_register_write(NSA_REG_STEP_CONFIG2, 0x62);
    mir3da_register_write(NSA_REG_STEP_CONFIG3, 0x46);
    mir3da_register_write(NSA_REG_STEP_CONFIG4, 0x32);
    mir3da_register_write(NSA_REG_STEP_FILTER, 0xa2);	
end

function mir3da_close_step_counter(void)
	mir3da_register_mask_write(NSA_REG_STEP_FILTER, 0x80, 0x00);	
end


function mir3da_get_step()
    local steps=0
    local tmp_recv = mir3da_register_read(NSA_REG_STEPS_MSB, 2) 
    if tmp_recv~=nil and #tmp_recv ==2 then
        steps = string.byte(string.sub(tmp_recv,1,1))
        steps = steps * 256
        steps = steps + string.byte(string.sub(tmp_recv,2,2))

        steps =math.floor(steps/2)
    end
    log.info("#tmp_recv, tmp_recv:toHex(),steps", #tmp_recv, tmp_recv:toHex(),steps)
    return tostring( steps)
end























 
-- 读取传感器
function gsensor()
    log.info("gsensor start");
    if i2c.setup(i2c_id, i2c.SLOW, i2c_addr) ~= i2c.SLOW then
        i2c.close(i2c_id)
        log.warn("gsensor", "open i2c error.")
        return
    end
    mir3da_init();
    mir3da_open_step_counter()
    mir3da_open_interrupt(0x01)  --03
end

local viblist = {}
silen_cnt =0
lowpw_cnt =0

local function get_valid_vib(bqry)
    local valid_vib=0
    if bqry or #viblist >=9 then 
        for i=1, #viblist do
            if viblist[i] ~=0 then
                valid_vib = valid_vib +1
            end            
        end
    end  
    return valid_vib
end  

local function FUN_GS_INT1(msg)
    if msg==cpu.INT_GPIO_POSEDGE then
        vibb_cnt = vibb_cnt +1
        log.info("===#viblist===valid_vib===vibb_cnt======",#viblist,get_valid_vib(true),vibb_cnt);

        if app_main.FACT_MODE == 1 then
            sys.publish("GSENSOR_TEST", tostring(vibb_cnt), mir3da_get_step() )
        end
    end
end
pins.setup(pio.P0_9,FUN_GS_INT1,pio.NOPULL)
gsensor()




-- 每隔10秒判断震动状态，如果连续震动90秒，退出休眠静止
sys.timerLoopStart(function() 

    if app_main.FACT_MODE == 0 then
        if vibb_cnt > 0 then 
            table.insert(viblist,vibb_cnt)
            log.info("INSERT===#viblist===valid_vib===vibb_cnt======",#viblist,get_valid_vib(true),vibb_cnt);

            if vibb_cnt > 1 then
                silen_cnt=0
            end
        elseif vibb_cnt == 0 then
            table.insert(viblist,0)
            if silen_cnt <1000000  then 
                silen_cnt = silen_cnt +1
            end
        end

        if #viblist >9 then 
            table.remove(viblist,1)
        end


        vibb_cnt =0


        --mir3da_get_step()

        if app_main.DEP_SLEEP ==0 then 

            if battery.isUSBConnected() then 
                -----------------------------
                if battery.getVRbattEx() <3250  then
                    app_main.ENTER_SLEEP_MODE()
                end
            else
                log.info("======silen_cnt======",silen_cnt);
                if silen_cnt   >30 then
                    --插入USB 不让休眠 (电池电量超低的时候，除外)
                    --不插入USB 且电量小于20%，也不让休眠
            
                    silen_cnt =0
                    if battery.getCapacity() >20   then
                        ---mir3da_close_step_counter()
                        app_main.ENTER_SLEEP_MODE()
                    end
                end
            end
        else
            if battery.isUSBConnected() then 
                if battery.getVRbattEx() >3550  then
                    app_main.TRYING_WORK_MODE("usb connected b")
                end
            end

            if  get_valid_vib() >=6  and  battery.getVRbattEx() >= 3400 then  
                viblist ={}
                app_main.TRYING_WORK_MODE("vibb triggle")
            end
        end

        --电池电压太低了，争取最后报一次，就关机；
        if not  battery.isUSBConnected() then
            if battery.getVRbattEx() <3500  then
                lowpw_cnt = lowpw_cnt + 1
                if  lowpw_cnt >5 and  fina_rpt ==0 then 
                    fina_rpt =1
                
                    if app_main.DEP_SLEEP ==1 then 
                        app_main.ENTER_WORK_MODE("low power <3.4")
                    else
                        cxd_proto.cxd_heart_req()
                    end

                    log.info("low power will shut off anyway");

                    sys.timerStart(function() 
                        fina_rpt =0
                        rtos.poweroff()
                    end, 60000)
                end
            else
                lowpw_cnt =0
            end
        end
    end
end, 10 *1000)



