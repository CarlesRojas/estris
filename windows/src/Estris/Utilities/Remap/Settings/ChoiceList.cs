using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Estris.Core.Loc;

namespace Estris.Utilities.Remap;

public sealed record Choice<T>(string Title, T Value);

public sealed record ChoiceSection<T>(string Title, IReadOnlyList<Choice<T>> Choices);

/// A searchable, sectioned list to pick a key, button or action from.
public sealed class ChoiceList<T> : Grid
{
    private readonly IReadOnlyList<ChoiceSection<T>> sections;
    private readonly Action<T> choose;
    private readonly ListView list = new() { SelectionMode = ListViewSelectionMode.None, IsItemClickEnabled = true };
    private readonly Dictionary<object, T> values = [];
    private readonly AutoSuggestBox search = new()
    {
        PlaceholderText = T("Search"),
        QueryIcon = new SymbolIcon(Symbol.Find),
        Margin = new Thickness(12, 12, 12, 8),
    };

    public ChoiceList(IReadOnlyList<ChoiceSection<T>> sections, Action<T> choose)
    {
        this.sections = sections;
        this.choose = choose;
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Children.Add(search);
        SetRow(list, 1);
        Children.Add(list);
        search.TextChanged += (_, _) => Show();
        list.ItemClick += (_, e) =>
        {
            if (values.TryGetValue(e.ClickedItem, out var value)) choose(value);
        };
        Loaded += (_, _) => search.Focus(FocusState.Programmatic);
        Show();
    }

    private void Show()
    {
        var query = search.Text.Trim();
        list.Items.Clear();
        values.Clear();
        foreach (var section in sections)
        {
            var matches = query == "" || section.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                ? section.Choices
                : section.Choices.Where(c => c.Title.Contains(query, StringComparison.CurrentCultureIgnoreCase)).ToList();
            if (matches.Count == 0) continue;
            list.Items.Add(new ListViewHeaderItem { Content = section.Title });
            foreach (var choice in matches)
            {
                var label = new TextBlock { Text = choice.Title };
                var item = new ListViewItem { Content = label, MinHeight = 36 };
                values[item] = choice.Value;
                values[label] = choice.Value;
                list.Items.Add(item);
            }
        }
    }
}

/// The choices offered for each side of a mapping.
public static class Choices
{
    public static string Title(RemapInput input) =>
        input.IsMouse ? MouseButtons.Name(input.Code) : KeyCatalog.Name(input.Code);

    public static string Title(RemapOutput output) => output.Kind switch
    {
        OutputKind.Key => KeyCatalog.Name(output.Code),
        OutputKind.MouseButton => MouseButtons.Name(output.Code),
        OutputKind.Action => SystemActions.Title(output.Action!.Value),
        _ => T("Nothing"),
    };

    public static IReadOnlyList<ChoiceSection<RemapInput>> Inputs(InputDevice device)
    {
        var keys = KeySections(k => RemapInput.Key(k.Code));
        var buttons = new ChoiceSection<RemapInput>(T("Mouse Buttons"), MouseButtons.Remappable.Select(n => new Choice<RemapInput>(MouseButtons.Name(n), RemapInput.Button(n))).ToList());
        return device.Kind == DeviceKind.Mouse ? [buttons, .. keys] : [.. keys, buttons];
    }

    public static IReadOnlyList<ChoiceSection<RemapOutput>> Outputs()
    {
        var actions = SystemActions.Sections.Select(s => new ChoiceSection<RemapOutput>(
            s.Title, s.Actions.Select(a => new Choice<RemapOutput>(SystemActions.Title(a), RemapOutput.Run(a))).ToList()));
        var buttons = new ChoiceSection<RemapOutput>(T("Mouse Buttons"), MouseButtons.All.Select(n => new Choice<RemapOutput>(MouseButtons.Name(n), RemapOutput.Button(n))).ToList());
        var off = new ChoiceSection<RemapOutput>(T("Off"), [new Choice<RemapOutput>(T("Nothing"), RemapOutput.Nothing)]);
        return [.. actions, buttons, .. KeySections(k => RemapOutput.Key(k.Code)), off];
    }

    private static List<ChoiceSection<TValue>> KeySections<TValue>(Func<KeyInfo, TValue> value) =>
        KeyCatalog.All.GroupBy(k => k.Section).OrderBy(g => g.Key)
            .Select(g => new ChoiceSection<TValue>(KeyCatalog.SectionTitle(g.Key), g.Select(k => new Choice<TValue>(k.Name, value(k))).ToList()))
            .ToList();
}
