package pipeline.fit

class FitConfigure implements Serializable{
    private String stack_type
    private String target
    private String name
    private String group
    private String stack
    private int log_level
    private String extra_options
    private String label
    private String config_path = "pipeline/fit/stack_config.json"
    private def share_method = new pipeline.common.ShareMethod()

    FitConfigure(stack_type, target, name){
        this.stack_type = stack_type
        this.target = target
        this.name = name
    }

    def configure(){
        def props = share_method.parseJsonResource(this.config_path)
        this.group = props[stack_type][target][name]["GROUP"]
        this.stack = props[stack_type][target][name]["STACK"]
        this.log_level = props[stack_type][target][name]["LOG_LEVEL"]
        this.extra_options = props[stack_type][target][name]["EXTRA_OPTIONS"]
        this.label = props[stack_type][target][name]["LABEL"]
    }

    def getLabel(){
        return label
    }
    def getStackType(){
        return stack_type
    }
    def getTarget(){
        return target
    }
    def getName(){
        return name
    }
    def getGroup(){
        return group
    }
    def getStack(){
        return stack
    }
    def getLogLevel(){
        return log_level
    }
    def getExtraOptions(){
        return extra_options
    }
}

