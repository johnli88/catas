console.log("Start javascript");

$(document).ready(function() {
    console.log("Inside document");

    function getCollectionFormData(form) {
        // creates a FormData object and adds chips text
        var formData = new FormData(document.getElementById(form));
        var collect_time = 0
        if (formData.entries()) {
            for (var [key, value] of formData.entries()) { 
                console.log('formData', key, value);
                if ( key == 'assessType' && (value == 'workload' || value == 'workloadsku') ) {
                    collect_time = 240;
                } else {
                    if (key == 'collectTime' && collect_time > 0) {
                        collect_time = parseInt(value);
                        break;
                    }
                }
            }
        } else { console_log("formData entry empty")}
        return collect_time
    }

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    $('form').on('submit', async function() {
        console.log("submitted here.")
		var total_time = getCollectionFormData('collection_form');
        // var collectTime = $('input#collectTime').val();
        console.log("collect time value: " + total_time.toString());
    
        if (total_time) {
            var percent = 0
            for (percetage = 0; percent < 101; percent++) {
                // delay = Math.round(total_time/100)*1000+100);
                delay = total_time*10+100;
                console.log("delay: " + delay.toString()); 
                await sleep(delay);
                $('#progressBar').attr('aria-valuenow', percent).css('width', percent + '%').text(percent + '%');
            }
        }    
    });

    $('.updateButton').on('click', function() {
        var sqldb = $('input#button_sqldb').is(":checked");
        var sqlmi = $('input#button_sqlmi').is(":checked");
        console.log("show sqldb and sqlmi");
        console.log(sqldb, sqlmi);
        
        req = $.ajax({
            url : '/collect',
            type : 'POST',
            data : { azure_cost : "cost", sqldb : sqldb, sqlmi : sqlmi }
        });

        req.done(function() {
            $('#sidebar').fadeOut(1000).fadeIn(1000);
        });
    
    });

    $('.saveConfigButton').on('click', function() {
        var config_file = $('input#configFile').val();
        console.log("config_file");
        console.log(config_file);
        
        req = $.ajax({
            url : '/manage',
            type : 'POST',
            data : { catas_save : "yes", config_file : config_file }
        });
        $('#sidebar').fadeOut(1000).fadeIn(1000);

        req.done(function(data) {
            alert(data.msg);
        });
    })

    $('.loadConfigButton').on('click', function() {
        var config_file = $('input#configFile').val();
        console.log("config_file");
        console.log(config_file);
        
        req = $.ajax({
            url : '/manage',
            type : 'POST',
            data : { catas_load : "yes", config_file : config_file }
        });
        $('#sidebar').fadeOut(1000).fadeIn(1000);

        req.done(function(data) {
            if (data.result == 'err') {
                alert(data.msg);
            } 
            else {
                console.log("data.msg: " + data.msg)
                window.location = data.msg;
            }
        });

    })

});