function id = protocol_id(protocol)
%PROTOCOL_ID Stable identity including all update, sampling and stop rules.
id = mc.identity(mc.validate_protocol(protocol),'protocol-v1');
end
