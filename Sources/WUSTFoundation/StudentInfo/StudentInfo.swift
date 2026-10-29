public struct StudentInfo {
    public let name: String //姓名
    public let studentID: String //学号
    public let college: String //院系
    public let major: String //专业
    public let className: String //班级
    public let birthday: String //出生日期
    public let sex: String //性别
    public let nationality: String //民族
    public let hometown: String //籍贯
    public let idNumber: String //身份证号
    
    public init(
        name: String,
        studentID: String,
        college: String,
        major: String,
        className: String,
        birthday: String,
        sex: String,
        nationality: String,
        hometown: String,
        idNumber: String
    ) {
        self.name = name
        self.studentID = studentID
        self.college = college
        self.major = major
        self.className = className
        self.birthday = birthday
        self.sex = sex
        self.nationality = nationality
        self.hometown = hometown
        self.idNumber = idNumber
    }
    
}
