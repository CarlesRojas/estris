using System.Globalization;
using System.Reflection;
using System.Text.RegularExpressions;

namespace Estris.Core;

/// Translations, keyed by the English text as on the Mac. Every area keeps its own
/// Localization/&lt;language&gt;/&lt;area&gt;.strings; all of a language's files are read together.
/// T("Some text") for fixed text; T("%@ of %lld", a, b) fills in values in order.
public static partial class Loc
{
    public static readonly (string Code, string Name)[] Languages =
    [
        ("en", "English"), ("es", "Español"), ("fr", "Français"), ("pt-BR", "Português (Brasil)"),
        ("de", "Deutsch"), ("it", "Italiano"), ("ca", "Català"),
    ];

    /// "" follows Windows. A change applies after relaunching.
    public static Setting<string> Language { get; } = SettingsStore.Shared.Get("language", "");

    public static string Code { get; } = Resolve();
    public static CultureInfo Culture { get; } = new(Code);

    private static readonly Dictionary<string, string> Table = LoadTable();

    private static string Resolve()
    {
        if (Language.Value != "") return Language.Value;
        var culture = CultureInfo.CurrentUICulture;
        foreach (var (code, _) in Languages)
            if (code.Equals(culture.Name, StringComparison.OrdinalIgnoreCase)) return code;
        foreach (var (code, _) in Languages)
            if (code.Split('-')[0] == culture.TwoLetterISOLanguageName) return code;
        return "en";
    }

    private static Dictionary<string, string> LoadTable()
    {
        var table = new Dictionary<string, string>();
        var assembly = Assembly.GetExecutingAssembly();
        var prefix = Code.Replace('-', '_');
        foreach (var name in assembly.GetManifestResourceNames())
        {
            var folder = name.Split('\\', '/')[0];
            if (!folder.Equals(Code, StringComparison.OrdinalIgnoreCase) && folder != prefix) continue;
            using var reader = new StreamReader(assembly.GetManifestResourceStream(name)!);
            foreach (Match line in EntryPattern().Matches(reader.ReadToEnd()))
                table[Unescape(line.Groups[1].Value)] = Unescape(line.Groups[2].Value);
        }
        return table;
    }

    private static string Unescape(string text) =>
        text.Replace("\\\"", "\"").Replace("\\n", "\n").Replace("\\\\", "\\");

    /// The text in the chosen language, or the English if it has none.
    public static string T(string key, params object[] values)
    {
        var text = Table.GetValueOrDefault(key, key);
        return values.Length == 0 ? text : Fill(text, values);
    }

    /// Fills %@ and %lld in order, or %1$@ by position, as the Mac's format strings do.
    private static string Fill(string text, object[] values)
    {
        var next = 0;
        return FormatPattern().Replace(text, match =>
        {
            var index = match.Groups[1].Success ? int.Parse(match.Groups[1].Value) - 1 : next++;
            return index < values.Length ? Convert.ToString(values[index], Culture) ?? "" : match.Value;
        });
    }

    [GeneratedRegex("""^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";""", RegexOptions.Multiline)]
    private static partial Regex EntryPattern();

    [GeneratedRegex(@"%(?:(\d+)\$)?(?:lld|ld|d|@)")]
    private static partial Regex FormatPattern();
}
