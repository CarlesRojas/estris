namespace Estris.Utilities.AccentMenu;

/// The accented versions of each letter, in the order the Mac's accent menu shows them.
internal static class Accents
{
    private static readonly Dictionary<char, string> Lowercase = new()
    {
        ['a'] = "àáâäæãåā",
        ['c'] = "çćč",
        ['e'] = "èéêëēėę",
        ['i'] = "îïíīįì",
        ['l'] = "ł",
        ['n'] = "ñń",
        ['o'] = "ôöòóœøōõ",
        ['s'] = "ßśš",
        ['u'] = "ûüùúū",
        ['y'] = "ÿ",
        ['z'] = "žźż",
    };

    private static readonly Dictionary<char, string> Uppercase = new()
    {
        ['A'] = "ÀÁÂÄÆÃÅĀ",
        ['C'] = "ÇĆČ",
        ['E'] = "ÈÉÊËĒĖĘ",
        ['I'] = "ÎÏÍĪĮÌ",
        ['L'] = "Ł",
        ['N'] = "ÑŃ",
        ['O'] = "ÔÖÒÓŒØŌÕ",
        ['S'] = "ŚŠ",
        ['U'] = "ÛÜÙÚŪ",
        ['Y'] = "Ÿ",
        ['Z'] = "ŽŹŻ",
    };

    /// Whether that virtual key is a letter key, A to Z.
    public static bool IsLetter(int vk) => vk is >= 'A' and <= 'Z';

    /// The accents of that letter key, in capitals or not; none for most.
    public static string For(int vk, bool isUppercase) =>
        (isUppercase ? Uppercase.GetValueOrDefault((char)vk) : Lowercase.GetValueOrDefault(char.ToLowerInvariant((char)vk))) ?? "";
}
