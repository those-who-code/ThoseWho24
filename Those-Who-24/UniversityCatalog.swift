import Foundation

struct UniversityOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let state: String?
    let stateCode: String?
    let country: String

    var location: String {
        [state, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func matches(_ query: String) -> Bool {
        let searchable = [name, state, stateCode, country]
            .compactMap { $0 }
            .joined(separator: " ")
        return searchable.localizedCaseInsensitiveContains(query)
    }
}

enum UniversityCatalog {
    static let none = UniversityOption(
        id: "non-school",
        name: "No university",
        state: nil,
        stateCode: nil,
        country: ""
    )

    static let universities: [UniversityOption] = [
        // United States
        us("air-force", "United States Air Force Academy", "Colorado", "CO"),
        us("alabama", "University of Alabama", "Alabama", "AL"),
        us("alaska", "University of Alaska Fairbanks", "Alaska", "AK"),
        us("arizona-state", "Arizona State University", "Arizona", "AZ"),
        us("arkansas", "University of Arkansas", "Arkansas", "AR"),
        us("auburn", "Auburn University", "Alabama", "AL"),
        us("baylor", "Baylor University", "Texas", "TX"),
        us("boise-state", "Boise State University", "Idaho", "ID"),
        us("boston-college", "Boston College", "Massachusetts", "MA"),
        us("boston-university", "Boston University", "Massachusetts", "MA"),
        us("brown", "Brown University", "Rhode Island", "RI"),
        us("byu", "Brigham Young University", "Utah", "UT"),
        us("caltech", "California Institute of Technology", "California", "CA"),
        us("carnegie-mellon", "Carnegie Mellon University", "Pennsylvania", "PA"),
        us("case-western", "Case Western Reserve University", "Ohio", "OH"),
        us("clemson", "Clemson University", "South Carolina", "SC"),
        us("columbia", "Columbia University", "New York", "NY"),
        us("connecticut", "University of Connecticut", "Connecticut", "CT"),
        us("cornell", "Cornell University", "New York", "NY"),
        us("dartmouth", "Dartmouth College", "New Hampshire", "NH"),
        us("delaware", "University of Delaware", "Delaware", "DE"),
        us("duke", "Duke University", "North Carolina", "NC"),
        us("emory", "Emory University", "Georgia", "GA"),
        us("florida", "University of Florida", "Florida", "FL"),
        us("florida-state", "Florida State University", "Florida", "FL"),
        us("george-washington", "George Washington University", "District of Columbia", "DC"),
        us("georgetown", "Georgetown University", "District of Columbia", "DC"),
        us("georgia", "University of Georgia", "Georgia", "GA"),
        us("georgia-tech", "Georgia Institute of Technology", "Georgia", "GA"),
        us("harvard", "Harvard University", "Massachusetts", "MA"),
        us("hawaii", "University of Hawaiʻi at Mānoa", "Hawaii", "HI"),
        us("houston", "University of Houston", "Texas", "TX"),
        us("howard", "Howard University", "District of Columbia", "DC"),
        us("idaho", "University of Idaho", "Idaho", "ID"),
        us("indiana", "Indiana University Bloomington", "Indiana", "IN"),
        us("iowa", "University of Iowa", "Iowa", "IA"),
        us("iowa-state", "Iowa State University", "Iowa", "IA"),
        us("johns-hopkins", "Johns Hopkins University", "Maryland", "MD"),
        us("kansas", "University of Kansas", "Kansas", "KS"),
        us("kansas-state", "Kansas State University", "Kansas", "KS"),
        us("kentucky", "University of Kentucky", "Kentucky", "KY"),
        us("lsu", "Louisiana State University", "Louisiana", "LA"),
        us("maine", "University of Maine", "Maine", "ME"),
        us("maryland", "University of Maryland, College Park", "Maryland", "MD"),
        us("miami", "University of Miami", "Florida", "FL"),
        us("michigan-state", "Michigan State University", "Michigan", "MI"),
        us("minnesota", "University of Minnesota Twin Cities", "Minnesota", "MN"),
        us("mississippi", "University of Mississippi", "Mississippi", "MS"),
        us("mississippi-state", "Mississippi State University", "Mississippi", "MS"),
        us("missouri", "University of Missouri", "Missouri", "MO"),
        us("mit", "Massachusetts Institute of Technology", "Massachusetts", "MA"),
        us("montana", "University of Montana", "Montana", "MT"),
        us("montana-state", "Montana State University", "Montana", "MT"),
        us("naval-academy", "United States Naval Academy", "Maryland", "MD"),
        us("nebraska", "University of Nebraska–Lincoln", "Nebraska", "NE"),
        us("nevada-reno", "University of Nevada, Reno", "Nevada", "NV"),
        us("new-hampshire", "University of New Hampshire", "New Hampshire", "NH"),
        us("new-mexico", "University of New Mexico", "New Mexico", "NM"),
        us("new-mexico-state", "New Mexico State University", "New Mexico", "NM"),
        us("notre-dame", "University of Notre Dame", "Indiana", "IN"),
        us("nyu", "New York University", "New York", "NY"),
        us("north-carolina-state", "North Carolina State University", "North Carolina", "NC"),
        us("north-dakota", "University of North Dakota", "North Dakota", "ND"),
        us("north-dakota-state", "North Dakota State University", "North Dakota", "ND"),
        us("northeastern", "Northeastern University", "Massachusetts", "MA"),
        us("northwestern", "Northwestern University", "Illinois", "IL"),
        us("ohio-state", "Ohio State University", "Ohio", "OH"),
        us("oklahoma", "University of Oklahoma", "Oklahoma", "OK"),
        us("oklahoma-state", "Oklahoma State University", "Oklahoma", "OK"),
        us("oregon", "University of Oregon", "Oregon", "OR"),
        us("oregon-state", "Oregon State University", "Oregon", "OR"),
        us("penn-state", "Pennsylvania State University", "Pennsylvania", "PA"),
        us("princeton", "Princeton University", "New Jersey", "NJ"),
        us("purdue", "Purdue University", "Indiana", "IN"),
        us("rice", "Rice University", "Texas", "TX"),
        us("rutgers", "Rutgers University–New Brunswick", "New Jersey", "NJ"),
        us("south-carolina", "University of South Carolina", "South Carolina", "SC"),
        us("south-dakota", "University of South Dakota", "South Dakota", "SD"),
        us("south-dakota-state", "South Dakota State University", "South Dakota", "SD"),
        us("stanford", "Stanford University", "California", "CA"),
        us("syracuse", "Syracuse University", "New York", "NY"),
        us("temple", "Temple University", "Pennsylvania", "PA"),
        us("tennessee", "University of Tennessee, Knoxville", "Tennessee", "TN"),
        us("texas-am", "Texas A&M University", "Texas", "TX"),
        us("tufts", "Tufts University", "Massachusetts", "MA"),
        us("tulane", "Tulane University", "Louisiana", "LA"),
        us("uc-berkeley", "University of California, Berkeley", "California", "CA"),
        us("uc-davis", "University of California, Davis", "California", "CA"),
        us("uc-irvine", "University of California, Irvine", "California", "CA"),
        us("uc-santa-barbara", "University of California, Santa Barbara", "California", "CA"),
        us("ucsd", "University of California, San Diego", "California", "CA"),
        us("uchicago", "University of Chicago", "Illinois", "IL"),
        us("ucla", "University of California, Los Angeles", "California", "CA"),
        us("uiuc", "University of Illinois Urbana-Champaign", "Illinois", "IL"),
        us("umass-amherst", "University of Massachusetts Amherst", "Massachusetts", "MA"),
        us("umich", "University of Michigan", "Michigan", "MI"),
        us("unc", "University of North Carolina at Chapel Hill", "North Carolina", "NC"),
        us("upenn", "University of Pennsylvania", "Pennsylvania", "PA"),
        us("usc", "University of Southern California", "California", "CA"),
        us("utexas", "University of Texas at Austin", "Texas", "TX"),
        us("utah", "University of Utah", "Utah", "UT"),
        us("vermont", "University of Vermont", "Vermont", "VT"),
        us("vanderbilt", "Vanderbilt University", "Tennessee", "TN"),
        us("virginia", "University of Virginia", "Virginia", "VA"),
        us("virginia-tech", "Virginia Tech", "Virginia", "VA"),
        us("wake-forest", "Wake Forest University", "North Carolina", "NC"),
        us("washington-state", "Washington State University", "Washington", "WA"),
        us("uw", "University of Washington", "Washington", "WA"),
        us("washu", "Washington University in St. Louis", "Missouri", "MO"),
        us("west-virginia", "West Virginia University", "West Virginia", "WV"),
        us("wisconsin", "University of Wisconsin–Madison", "Wisconsin", "WI"),
        us("wyoming", "University of Wyoming", "Wyoming", "WY"),
        us("yale", "Yale University", "Connecticut", "CT"),

        // Canada
        intl("alberta", "University of Alberta", "Alberta", "AB", "Canada"),
        intl("british-columbia", "University of British Columbia", "British Columbia", "BC", "Canada"),
        intl("mcgill", "McGill University", "Quebec", "QC", "Canada"),
        intl("mcmaster", "McMaster University", "Ontario", "ON", "Canada"),
        intl("montreal", "Université de Montréal", "Quebec", "QC", "Canada"),
        intl("ottawa", "University of Ottawa", "Ontario", "ON", "Canada"),
        intl("queens", "Queen's University", "Ontario", "ON", "Canada"),
        intl("simon-fraser", "Simon Fraser University", "British Columbia", "BC", "Canada"),
        intl("utoronto", "University of Toronto", "Ontario", "ON", "Canada"),
        intl("waterloo", "University of Waterloo", "Ontario", "ON", "Canada"),

        // United Kingdom and Ireland
        intl("cambridge", "University of Cambridge", "England", nil, "United Kingdom"),
        intl("edinburgh", "University of Edinburgh", "Scotland", nil, "United Kingdom"),
        intl("imperial", "Imperial College London", "England", nil, "United Kingdom"),
        intl("kings-college-london", "King's College London", "England", nil, "United Kingdom"),
        intl("lse", "London School of Economics and Political Science", "England", nil, "United Kingdom"),
        intl("manchester", "University of Manchester", "England", nil, "United Kingdom"),
        intl("oxford", "University of Oxford", "England", nil, "United Kingdom"),
        intl("st-andrews", "University of St Andrews", "Scotland", nil, "United Kingdom"),
        intl("ucl", "University College London", "England", nil, "United Kingdom"),
        intl("trinity-dublin", "Trinity College Dublin", "Leinster", nil, "Ireland"),

        // Europe
        intl("amsterdam", "University of Amsterdam", nil, nil, "Netherlands"),
        intl("copenhagen", "University of Copenhagen", nil, nil, "Denmark"),
        intl("delft", "Delft University of Technology", nil, nil, "Netherlands"),
        intl("epfl", "EPFL", "Vaud", nil, "Switzerland"),
        intl("eth-zurich", "ETH Zurich", "Zurich", nil, "Switzerland"),
        intl("heidelberg", "Heidelberg University", "Baden-Württemberg", nil, "Germany"),
        intl("ku-leuven", "KU Leuven", "Flemish Brabant", nil, "Belgium"),
        intl("lmu-munich", "LMU Munich", "Bavaria", nil, "Germany"),
        intl("paris-saclay", "Paris-Saclay University", "Île-de-France", nil, "France"),
        intl("sorbonne", "Sorbonne University", "Île-de-France", nil, "France"),
        intl("technical-university-munich", "Technical University of Munich", "Bavaria", nil, "Germany"),

        // Asia and the Middle East
        intl("chinese-university-hong-kong", "Chinese University of Hong Kong", nil, nil, "Hong Kong"),
        intl("hkust", "Hong Kong University of Science and Technology", nil, nil, "Hong Kong"),
        intl("iit-bombay", "Indian Institute of Technology Bombay", "Maharashtra", nil, "India"),
        intl("kaist", "KAIST", "Daejeon", nil, "South Korea"),
        intl("kyoto", "Kyoto University", "Kyoto", nil, "Japan"),
        intl("national-taiwan", "National Taiwan University", "Taipei", nil, "Taiwan"),
        intl("nus", "National University of Singapore", nil, nil, "Singapore"),
        intl("peking", "Peking University", "Beijing", nil, "China"),
        intl("seoul-national", "Seoul National University", "Seoul", nil, "South Korea"),
        intl("technion", "Technion – Israel Institute of Technology", "Haifa", nil, "Israel"),
        intl("tel-aviv", "Tel Aviv University", "Tel Aviv", nil, "Israel"),
        intl("tokyo", "University of Tokyo", "Tokyo", nil, "Japan"),
        intl("tsinghua", "Tsinghua University", "Beijing", nil, "China"),

        // Australia, New Zealand, Africa, and Latin America
        intl("anu", "Australian National University", "Australian Capital Territory", "ACT", "Australia"),
        intl("auckland", "University of Auckland", "Auckland", nil, "New Zealand"),
        intl("cape-town", "University of Cape Town", "Western Cape", nil, "South Africa"),
        intl("melbourne", "University of Melbourne", "Victoria", "VIC", "Australia"),
        intl("monash", "Monash University", "Victoria", "VIC", "Australia"),
        intl("new-south-wales", "University of New South Wales", "New South Wales", "NSW", "Australia"),
        intl("pontifical-catholic-chile", "Pontifical Catholic University of Chile", "Santiago", nil, "Chile"),
        intl("sao-paulo", "University of São Paulo", "São Paulo", "SP", "Brazil"),
        intl("sydney", "University of Sydney", "New South Wales", "NSW", "Australia"),
        intl("unam", "National Autonomous University of Mexico", "Mexico City", nil, "Mexico")
    ]
    .sorted {
        if $0.country != $1.country { return $0.country < $1.country }
        if $0.state != $1.state { return ($0.state ?? "") < ($1.state ?? "") }
        return $0.name < $1.name
    }

    static func displayName(for id: String) -> String {
        if id == none.id { return none.name }
        return universities.first(where: { $0.id == id })?.name ?? id
    }

    private static func us(_ id: String, _ name: String, _ state: String, _ stateCode: String) -> UniversityOption {
        UniversityOption(id: id, name: name, state: state, stateCode: stateCode, country: "United States")
    }

    private static func intl(
        _ id: String,
        _ name: String,
        _ state: String?,
        _ stateCode: String?,
        _ country: String
    ) -> UniversityOption {
        UniversityOption(id: id, name: name, state: state, stateCode: stateCode, country: country)
    }
}
