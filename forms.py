from flask_wtf import FlaskForm
from wtforms import StringField, IntegerField, SubmitField, BooleanField, SelectField, RadioField
from wtforms.validators import DataRequired, Length, Email, EqualTo, regexp, ValidationError, NumberRange
from flask_wtf.file import FileField, FileRequired, FileAllowed
import os.path
from config import config, print_config

def check_csv_file(filename):
    file_type = filename[-3:]
    if file_type.lower() != 'csv':
        return "File type is invalid."
    if not os.path.isfile(filename):
        return "File does not exist."
    return ""

class ValidationForm(FlaskForm):
    assessname = StringField('Assessment name',
                           validators=[DataRequired(), Length(min=3, max=50)])
    filename = StringField('Put your input server CSV file name including absolute file path', 
                           validators=[DataRequired(), Length(min=5, max=200)])
    #filename = FileField('Select Your File', validators=[FileRequired(), FileAllowed(['csv'], 'CSV file only!')])
    validationType = SelectField('Validation type', [DataRequired()],
                        choices=[('ValidateHost', 'SQL Server Host Connection'),
                                 ('ValidateSql', 'SQL Server Instance Connection'),
                                 ('ValidateBoth', 'SQL Server Host and Instance Connection')])
    print_config("validation form")
    submit = SubmitField('Validate')

    def validate_assessname(self, assessname):
        config['assess_name'] = assessname.data

    def validate_filename(self, filename):
        file = check_csv_file(filename.data)    # If no issue, return an empty string
        if file:
            raise ValidationError(f"{file} Please choose a different one.")
        config['input_csv_file'] = filename.data

    def validate_validationType(self, validationType):
        config['validation_type'] = validationType.data

class AssessmentForm(FlaskForm):
    assessname = StringField('Assessment name',
                           validators=[DataRequired(), Length(min=3, max=50)], default=config['assess_name'])
    filename = StringField('Put your input server CSV file name including absolute file path', 
                           validators=[DataRequired(), Length(min=5, max=200)], default=config['input_csv_file'])
    #filename = FileField('Select Your File', validators=[FileRequired(), FileAllowed(['csv'], 'CSV file only!')])
    outputFolder = StringField('Put your output destination path here (optional)', 
                           validators=[DataRequired(), Length(min=5, max=200)], default=config['output_folder'])
    reportName = StringField('Put your output report name here (optional)', 
                           validators=[DataRequired(), Length(min=3, max=50)], default=config['output_report_name'])
    reportFormat = SelectField('Output report format', [DataRequired()],
                        choices=[('dma', 'DMA'),
                                 ('json', 'JSON'),
                                 ('csv', 'CSV'),
                                 ('all', 'DMA and JSON')], default=config['output_report_format'])
    assessType = SelectField('Assessment type', [DataRequired()],
                        choices=[('Both', 'SQL Feature Parity and Compatibility Level'),
                                 ('Feature', 'SQL Feature Parity'),                  
                                 ('Compat', 'SQL Compatibility Level'),
                                 ('Evaluate', 'SQL Target Evaluation')], default=config['assess_type'])
    target = SelectField('Target platform', [DataRequired()],
                        choices=[('SQLdb', 'Azure SQL Database'),
                                 ('SQLmi', 'Azure SQL Managed Instance')], default=config['target_platform'])
    print_config("Assessment form")
    submit = SubmitField('Assess')

    def validate_assessname(self, assessname):
        config['assess_name'] = assessname.data

    def validate_filename(self, filename):
        file = check_csv_file(filename.data)    # If no issue, return an empty string
        if file:
            raise ValidationError(f"{file} Please choose a different one.")
        config['input_csv_file'] = filename.data

    def validate_outputFolder(self, outputFolder):
        config['output_folder'] = outputFolder.data

    def validate_reportName(self, reportName):
        config['output_report_name'] = reportName.data

    def validate_reportFormat(self, reportFormat):
        config['output_report_format'] = reportFormat.data

    def validate_assessType(self, assessType):
        config['assess_type'] = assessType.data

    def validate_target(self, target):
        config['target_platform'] = target.data


class CollectionForm(FlaskForm):
    assessname = StringField('Assessment name',
                           validators=[DataRequired(), Length(min=3, max=50)], default=config['assess_name'])
    filename = StringField('CSV file with absolute path (SQL Server info for workload collection and estimation)', 
                           validators=[DataRequired(), Length(min=5, max=200)], default=config['count_csv_file'])
    #filename = FileField('Select Your File', validators=[FileRequired(), FileAllowed(['csv'], 'CSV file only!')])
    outputFolder = StringField('Put your output destination path here (optional)', 
                           validators=[DataRequired(), Length(min=5, max=200)], default=config['output_folder'])
    reportFormat = SelectField('Output report format', [DataRequired()],
                        choices=[('csv', 'CSV'),
                                 ('html', 'HTML')], default=config['count_csv_file'])
    assessType = SelectField('Action type', [DataRequired()],
                        choices=[('workload', 'Collect SQL Server Workload'),
                                 ('sku', 'Estimate Azure SQL Cost'),
                                 ('workloadsku', 'Collect SQL Server Workload and Estimate Azure SQL Cost')], default=config['assess_type'])
    dblist = StringField('Databases (optional, case sensitive and only valid when estimation)', 
                           validators=[Length(min=0, max=50000)], default=config['db_list'])
    subid = StringField('Azure subscription ID (required for estimation)', 
                           validators=[Length(min=0, max=36)], default=config['sub_id'])
    collectTime = IntegerField('Workload collection time in seconds (required for workload collection)', 
                        validators=[NumberRange(min=240, max=36000)], default=config['collect_time'])
    tenantid = StringField('Azure tenant ID (required for estimation)', 
                           validators=[Length(min=0, max=36)], default=config['tenant_id'])
    subid = StringField('Azure subscription ID (required for estimation)', 
                           validators=[Length(min=0, max=36)], default=config['sub_id'])
    clientid = StringField('Azure client ID (required for estimation)', 
                           validators=[Length(min=0, max=36)], default=config['client_id'])
    print_config("Collection form")
    submit = SubmitField('Submit')

    def validate_assessname(self, assessname):
        config['assess_name'] = assessname.data

    def validate_filename(self, filename):
        file = check_csv_file(filename.data)    # If no issue, return an empty string
        if file:
            raise ValidationError(f"{file} Please choose a different one.")
        config['input_csv_file'] = filename.data

    def validate_outputFolder(self, outputFolder):
        config['output_folder'] = outputFolder.data

    def validate_reportFormat(self, reportFormat):
        if (reportFormat.data == 'html' and self.assessType == 'workload'):
            raise ValidationError("Please choose CSV report format for workload collection.")
        config['output_report_format'] = reportFormat.data

    def validate_assessType(self, assessType):
        if (self.reportFormat.data == 'html' and assessType == 'workload'):
            raise ValidationError("Please choose CSV report format for workload collection.")
        config['assess_type'] = assessType.data

    def validate_dblist(self, dblist):
        config['db_list'] = dblist.data

    def validate_collectTime(self, collectTime):
        config['collect_time'] = collectTime.data

    def validate_tenantid(self, tenantid):
        if ((len(tenantid.data) != 0 and len(tenantid.data) != 36) or 
            (self.assessType.data != 'workload' and len(tenantid.data) == 0)):
            raise ValidationError("Please make sure tenant ID is correct.")
        config['tenant_id'] = tenantid.data

    def validate_subid(self, subid):
        if (len(subid.data) != 0 and len(subid.data) != 36 or 
            (self.assessType.data != 'workload' and len(subid.data) == 0)):
            raise ValidationError("Please make sure subscription ID is correct.")
        config['sub_id'] = subid.data

    def validate_clientid(self, clientid):
        if (len(clientid.data) != 0 and len(clientid.data) != 36 or 
            (self.assessType.data != 'workload' and len(clientid.data) == 0)):
            raise ValidationError("Please make sure client ID is correct.")
        config['client_id'] = clientid.data


