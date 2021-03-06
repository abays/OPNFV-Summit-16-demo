def get_networks_template(network_service, parent_service)
  # Get all networks for this service and create a Heat template to represent them
  
  template = nil
  template_content = {}
  
  template_content['heat_template_version'] = '2013-05-23'
  template_content['resources'] = {}
  
  network_service.direct_service_children.detect { |x| x.name == 'VNF Networks' }.direct_service_children.each do |vnf_network|
    
    vnf_network_properties = JSON.parse(vnf_network.custom_get('properties'))
    cidr = vnf_network_properties['cidr']
    
    network_name = "#{parent_service.name}_#{vnf_network.name}_net"
    
    template_content['resources'][network_name] = {}
    template_content['resources'][network_name]['properties'] = {}
    template_content['resources'][network_name]['properties']['name'] = "#{vnf_network.name}"
    template_content['resources'][network_name]['type'] = 'OS::Neutron::Net'
    
    subnet_name = "#{parent_service.name}_#{vnf_network.name}_subnet"
    
    template_content['resources'][subnet_name] = {}
    template_content['resources'][subnet_name]['properties'] = {}
    template_content['resources'][subnet_name]['properties']['name'] = "#{vnf_network.name}_subnet"
    template_content['resources'][subnet_name]['properties']['cidr'] = cidr
    template_content['resources'][subnet_name]['properties']['network_id'] = {}
    template_content['resources'][subnet_name]['properties']['network_id']['get_resource'] = network_name
    template_content['resources'][subnet_name]['type'] = 'OS::Neutron::Subnet'
  end
  
  vnf_networks_template_name = "#{parent_service.name} #{Time.now.to_i} networks"
  
  template = $evm.vmdb('orchestration_template_hot').create(
    :name      => vnf_networks_template_name, 
      :orderable => true, 
      :content   => YAML.dump(template_content))
  template
end

def deploy_networks(network_service, parent_service)
  
  network_orchestration_manager = $evm.vmdb('ManageIQ_Providers_Openstack_CloudManager').find_by_name("openstack-nfvpe")
  networks_template = get_networks_template(network_service, parent_service)
  networks_orchestration = deploy_networks_stack(network_orchestration_manager, parent_service, networks_template)
  
  while networks_orchestration.orchestration_stack_status[0] == 'transient'
    $evm.log(:info, "Waiting for networks to spawn: #{networks_orchestration.orchestration_stack_status} (current state)")
    sleep(1)
  end
end

def deploy_networks_stack(orchestration_manager, parent_service, template)

  orchestration_service = $evm.vmdb('ServiceOrchestration').create(
    :name => "#{parent_service.name} networks")

  orchestration_service.stack_name             = "#{parent_service.name}_networks"
  orchestration_service.orchestration_template = template
  $evm.log(:info, "AJB template: #{template}")
  orchestration_service.orchestration_manager  = orchestration_manager
  orchestration_service.stack_options          = {:attributes => {}}
  orchestration_service.display                = true
  orchestration_service.parent_service         = parent_service
  orchestration_service.deploy_orchestration_stack 
  
  orchestration_service
end  

begin
  nsd = $evm.get_state_var(:nsd)
  $evm.log("info", "Listing nsd #{nsd}")
  $evm.log("info", "Listing Root Object Attributes:")
  $evm.root.attributes.sort.each { |k, v| $evm.log("info", "\t#{k}: #{v}") }
  $evm.log("info", "===========================================")
  
  parent_service = $evm.root['service_template_provision_task'].destination
  parent_service.name = $evm.root.attributes['dialog_service_name']
  
  network_service = $evm.vmdb('service', $evm.root.attributes['dialog_network_service'])
  
  deploy_networks(network_service, parent_service)
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}") 
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
