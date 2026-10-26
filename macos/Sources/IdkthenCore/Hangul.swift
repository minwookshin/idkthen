import Foundation

/// Independent Unicode Hangul composition for the standard Korean two-set keyboard.
/// This converts committed text; it is not an input method or a Korean language model.
public enum Hangul {
    static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    static let finals = Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    static let initialKeys = ["r","R","s","e","E","f","a","q","Q","t","T","d","w","W","c","z","x","v","g"]
    static let vowelKeys = ["k","o","i","O","j","p","u","P","h","hk","ho","hl","y","n","nj","np","nl","b","m","ml","l"]
    static let finalKeys = ["","r","R","rt","s","sw","sg","e","f","fr","fa","fq","ft","fx","fv","fg","a","q","qt","t","T","d","w","c","z","x","v","g"]
    static let shifted: Set<Character> = Set("REQTWOP")
    static let keys: [Character: Character] = {
        var result: [Character: Character] = [:]
        for (j, k) in zip(initials, initialKeys) { result[Character(k)] = j }
        for (j, k) in zip(vowels, vowelKeys) where k.count == 1 { result[Character(k)] = j }
        return result
    }()
    static let vowelCombinations: [String: Int] = ["8,0":9,"8,1":10,"8,20":11,"13,4":14,"13,5":15,"13,20":16,"18,20":19]
    static let finalCombinations: [String: Int] = ["1,19":3,"4,22":5,"4,27":6,"8,1":9,"8,16":10,"8,17":11,"8,19":12,"8,25":13,"8,26":14,"8,27":15,"17,19":18]
    static let splitFinals: [Int: (Int, Int)] = [3:(1,9),5:(4,12),6:(4,18),9:(8,0),10:(8,6),11:(8,7),12:(8,9),13:(8,16),14:(8,17),15:(8,18),18:(17,9)]

    public static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x3163).contains($0.value) }
    }
    public static func fromQWERTY(_ text: String) -> String {
        var output = "", l: Int? = nil, v: Int? = nil, t = 0
        func flush() {
            if let a = l, let b = v { output.unicodeScalars.append(UnicodeScalar(0xAC00 + a * 588 + b * 28 + t)!) }
            else if let a = l { output.append(initials[a]) }
            else if let b = v { output.append(vowels[b]) }
            l = nil; v = nil; t = 0
        }
        for original in text {
            let normalized = shifted.contains(original) ? original : Character(String(original).lowercased())
            guard let jamo = keys[normalized] else { flush(); output.append(original); continue }
            if let nextV = vowels.firstIndex(of: jamo) {
                if v == nil { v = nextV; continue }
                if t > 0 {
                    let nextL: Int
                    if let split = splitFinals[t] { t = split.0; nextL = split.1 }
                    else { nextL = initials.firstIndex(of: finals[t])!; t = 0 }
                    flush(); l = nextL; v = nextV
                } else if let combined = vowelCombinations["\(v!),\(nextV)"] { v = combined }
                else { flush(); v = nextV }
            } else if let nextL = initials.firstIndex(of: jamo) {
                if l == nil && v == nil { l = nextL; continue }
                if l != nil && v != nil, let nextT = finals.firstIndex(of: jamo) {
                    if t == 0 { t = nextT }
                    else if let combined = finalCombinations["\(t),\(nextT)"] { t = combined }
                    else { flush(); l = nextL }
                } else { flush(); l = nextL }
            }
        }
        flush(); return output
    }
    public static func toQWERTY(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            let n = Int(scalar.value)
            if (0xAC00...0xD7A3).contains(n) {
                let s = n - 0xAC00
                result += initialKeys[s / 588] + vowelKeys[(s % 588) / 28] + finalKeys[s % 28]
            } else {
                let c = Character(String(scalar))
                if let i = initials.firstIndex(of: c) { result += initialKeys[i] }
                else if let i = vowels.firstIndex(of: c) { result += vowelKeys[i] }
                else if let i = finals.firstIndex(of: c), i > 0 { result += finalKeys[i] }
                else { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }
}

/// Explicit standard Ukrainian letter mapping, not transliteration. Custom/phonetic layouts are unsupported.
public enum UkrainianLayout {
    private static let forward: [Character: Character] = Dictionary(uniqueKeysWithValues:
        zip(Array("qwertyuiop[]asdfghjkl;'zxcvbnm,."), Array("йцукенгшщзхїфівапролджєячсмитьбю")))
    private static let backward = Dictionary(uniqueKeysWithValues: forward.map { ($0.value, $0.key) })
    public static func containsUkrainian(_ text: String) -> Bool { text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) } }
    public static func convert(_ text: String, toEnglish: Bool) -> String {
        let map = toEnglish ? backward : forward
        return text.map { c in
            if let exact = map[c] { return String(exact) }
            let lower = String(c).lowercased()
            if lower.count == 1, let result = map[Character(lower)] { return String(result).uppercased() }
            return String(c)
        }.joined()
    }
}
