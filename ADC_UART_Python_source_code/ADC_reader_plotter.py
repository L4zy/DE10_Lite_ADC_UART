'''
recieves a frame of 16 bit signed values and plots them
'''
import matplotlib.pyplot as plt
import serial
from bitstring import BitArray

frame_size = 512

class uart_manager(object):
    
    def __init__(self):
        pass

    def open_port(self):
        """Handles UART stuff """
        self.ser = serial.Serial()
        self.ser.baudrate = 115200
        self.ser.port = 'COM10'
        print(self.ser)
        self.ser.open()
        
    def get_vals(self):
        i = 0
        was_upper = 1
        waveform = []

        while (i < frame_size*2):
            i = i + 1
            if was_upper == 1:
                was_upper = 0
                lower = self.ser.read()
                
            elif was_upper == 0:
                was_upper = 1
                upper = self.ser.read()
                
                value = upper + lower
                #print(value)
                value_int = int.from_bytes(value, "big")
                print(value_int)
                voltage = value_int * 0.001220703125
                #print(voltage,'V')
                waveform.append(voltage)
                #print(len(waveform))
                
        return waveform   
        
class wave_plotter():
    
    def __init__(self):
        self.x = range(0,frame_size*12, 12)
    
    def plot(self, wave):
        plt.plot(self.x, wave, '-ok')
        plt.ylabel('V')
        plt.show()
    
if __name__ == "__main__":
    um = uart_manager()
    wp = wave_plotter()

    um.open_port()

    while(1):
        wav = um.get_vals()
        wp.plot(wav)



        
        
        
        
        
        

        
        
        
        
        
        
        
        
        
        
        
        
        
        
