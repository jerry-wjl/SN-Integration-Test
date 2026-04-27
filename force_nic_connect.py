import sys
import ssl
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim

def force_connect(host, user, pwd, vm_name):
    si = None
    try:
        context = ssl._create_unverified_context()
        si = SmartConnect(host=host, user=user, pwd=pwd, sslContext=context)
        content = si.RetrieveContent()
        
        container = content.viewManager.CreateContainerView(content.rootFolder, [vim.VirtualMachine], True)
        vm = next((v for v in container.view if v.name == vm_name), None)
        
        if not vm:
            print(f"FAILED: VM {vm_name} not found.")
            sys.exit(1)

        device_specs = []
        for device in vm.config.hardware.device:
            if isinstance(device, vim.vm.device.VirtualEthernetCard):
                print(f"Found NIC: {device.deviceInfo.label}. Sending Reconfig Task...")
                
                device.connectable.connected = True
                device.connectable.startConnected = True
                device.connectable.allowGuestControl = True
                
                spec = vim.vm.device.VirtualDeviceSpec()
                spec.operation = vim.vm.device.VirtualDeviceSpec.Operation.edit
                spec.device = device
                device_specs.append(spec)

        if device_specs:
            reconfig_spec = vim.vm.ConfigSpec()
            reconfig_spec.deviceChange = device_specs
            task = vm.ReconfigVM_Task(spec=reconfig_spec)
            print(f"Task successfully triggered for {vm_name}!")
        else:
            print(f"No NIC found on {vm_name}.")

    except Exception as e:
        print(f"Error occurred: {str(e)}")
        sys.exit(1)
    finally:
        if si:
            Disconnect(si)

if __name__ == "__main__":
    force_connect(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
