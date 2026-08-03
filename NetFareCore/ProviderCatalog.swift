import Foundation

public enum ProviderCatalog {
    public static let all: [ProviderRecord] = [
        ProviderRecord(id: "att", name: "AT&T", aliases: ["att fiber", "at&t fiber", "att internet", "at&t internet"], website: URL(string: "https://www.att.com/internet/")),
        ProviderRecord(id: "comcast", name: "Comcast Xfinity", aliases: ["xfinity", "comcast", "comcast xfinity"], website: URL(string: "https://www.xfinity.com/learn/internet-service")),
        ProviderRecord(id: "spectrum", name: "Spectrum", aliases: ["charter", "spectrum internet"], website: URL(string: "https://www.spectrum.com/internet")),
        ProviderRecord(id: "verizon-fios", name: "Verizon Fios", aliases: ["verizon", "fios", "verizon fios internet"], website: URL(string: "https://www.verizon.com/home/internet/fios/")),
        ProviderRecord(id: "verizon-5g", name: "Verizon 5G Home", aliases: ["verizon 5g home", "verizon wireless home internet"], website: URL(string: "https://www.verizon.com/5g/home/")),
        ProviderRecord(id: "t-mobile", name: "T-Mobile 5G Home Internet", aliases: ["t mobile", "tmobile", "t-mobile home"], website: URL(string: "https://www.t-mobile.com/home-internet")),
        ProviderRecord(id: "cox", name: "Cox", aliases: ["cox communications", "cox internet"], website: URL(string: "https://www.cox.com/residential/internet.html")),
        ProviderRecord(id: "frontier", name: "Frontier", aliases: ["frontier fiber", "frontier communications"], website: URL(string: "https://frontier.com/")),
        ProviderRecord(id: "centurylink", name: "CenturyLink", aliases: ["century link", "centurylink internet"], website: URL(string: "https://www.centurylink.com/internet/")),
        ProviderRecord(id: "quantum", name: "Quantum Fiber", aliases: ["quantum fiber", "quantum"], website: URL(string: "https://www.quantumfiber.com/")),
        ProviderRecord(id: "google-fiber", name: "Google Fiber", aliases: ["google fiber internet"], website: URL(string: "https://fiber.google.com/")),
        ProviderRecord(id: "optimum", name: "Optimum", aliases: ["altice optimum", "optimum online"], website: URL(string: "https://www.optimum.com/internet")),
        ProviderRecord(id: "astound", name: "Astound Broadband", aliases: ["astound", "rcn", "wow internet"], website: URL(string: "https://www.astound.com/internet/")),
        ProviderRecord(id: "mediacom", name: "Mediacom", aliases: ["mediacom cable", "mediacom internet"], website: URL(string: "https://mediacomcable.com/internet/")),
        ProviderRecord(id: "windstream", name: "Kinetic by Windstream", aliases: ["windstream", "kinetic"], website: URL(string: "https://www.windstream.com/")),
        ProviderRecord(id: "ziply", name: "Ziply Fiber", aliases: ["ziply", "ziply fiber internet"], website: URL(string: "https://ziplyfiber.com/")),
        ProviderRecord(id: "sonic", name: "Sonic", aliases: ["sonic internet"], website: URL(string: "https://www.sonic.com/")),
        ProviderRecord(id: "metronet", name: "Metronet", aliases: ["metronet fiber"], website: URL(string: "https://www.metronet.com/")),
        ProviderRecord(id: "lumos", name: "Lumos", aliases: ["lumos fiber"], website: URL(string: "https://www.lumosfiber.com/")),
        ProviderRecord(id: "starlink", name: "Starlink", aliases: ["starlink internet"], website: URL(string: "https://www.starlink.com/")),
        ProviderRecord(id: "viasat", name: "Viasat", aliases: ["viasat internet"], website: URL(string: "https://www.viasat.com/")),
        ProviderRecord(id: "hughesnet", name: "Hughesnet", aliases: ["hughes net", "hughesnet internet"], website: URL(string: "https://www.hughesnet.com/")),
        ProviderRecord(id: "breezeline", name: "Breezeline", aliases: ["atlantic broadband", "breezeline internet"], website: URL(string: "https://www.breezeline.com/")),
        ProviderRecord(id: "bluepeak", name: "Bluepeak", aliases: ["bluepeak fiber"], website: URL(string: "https://mybluepeak.com/")),
        ProviderRecord(id: "altafiber", name: "altafiber", aliases: ["cincinnati bell", "alta fiber"], website: URL(string: "https://www.altafiber.com/")),
        ProviderRecord(id: "ting", name: "Ting Internet", aliases: ["ting fiber", "ting internet"], website: URL(string: "https://ting.com/internet")),
        ProviderRecord(id: "brightspeed", name: "Brightspeed", aliases: ["brightspeed fiber", "brightspeed internet"], website: URL(string: "https://www.brightspeed.com/")),
        ProviderRecord(id: "earthlink", name: "EarthLink", aliases: ["earthlink internet", "earthlink fiber"], website: URL(string: "https://www.earthlink.net/")),
        ProviderRecord(id: "tds", name: "TDS Telecom", aliases: ["tds", "tds fiber", "tds telecom"], website: URL(string: "https://tdstelecom.com/")),
        ProviderRecord(id: "consolidated", name: "Consolidated Communications", aliases: ["consolidated", "fidium", "fidium fiber"], website: URL(string: "https://www.consolidated.com/")),
        ProviderRecord(id: "gci", name: "GCI", aliases: ["gci alaska", "gci internet"], website: URL(string: "https://www.gci.com/")),
        ProviderRecord(id: "epb", name: "EPB Fiber Optics", aliases: ["epb", "epb fiber"], website: URL(string: "https://epb.com/")),
        ProviderRecord(id: "go-net-speed", name: "GoNetspeed", aliases: ["gonetspeed", "go netspeed"], website: URL(string: "https://gonetspeed.com/")),
        ProviderRecord(id: "vyve", name: "Vyve Broadband", aliases: ["vyve", "vyve broadband internet"], website: URL(string: "https://www.vyvebroadband.com/")),
        ProviderRecord(id: "armstrong", name: "Armstrong", aliases: ["armstrong cable", "armstrong internet"], website: URL(string: "https://www.armstrongonewire.com/")),
        ProviderRecord(id: "buckeye", name: "Buckeye Broadband", aliases: ["buckeye", "buckeye broadband"], website: URL(string: "https://www.buckeyebroadband.com/")),
        ProviderRecord(id: "wow", name: "WOW!", aliases: ["wow", "wideopenwest", "wide open west"], website: URL(string: "https://www.wowway.com/"))
    ]

    public static func match(_ query: String) -> ProviderRecord? {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return nil }
        return all.first { record in
            normalize(record.name) == normalized || record.aliases.contains { normalize($0) == normalized }
        }
    }

    public static func suggestions(for query: String, limit: Int = 6) -> [ProviderRecord] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return Array(all.prefix(limit)) }
        return all.filter { record in
            normalize(record.name).contains(normalized) || record.aliases.contains { normalize($0).contains(normalized) }
        }.prefix(limit).map { $0 }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}
