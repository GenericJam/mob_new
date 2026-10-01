# Template-assertion test: the generated Android text field reads the props
# the Mishka inputs and the theme set on it (MOB-197, MOB-237).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidTextFieldPropsTest do
  use ExUnit.Case, async: true

  @bridge Application.app_dir(
            :mob_new,
            "priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex"
          )

  setup_all do
    source = File.read!(@bridge)
    [_, rest] = String.split(source, "private fun MobTextField", parts: 2)
    [body | _] = String.split(rest, "private fun MobToggle", parts: 2)

    code =
      body
      |> String.split("\n")
      |> Enum.map_join("\n", &Regex.replace(~r|^\s*//.*$|, &1, ""))
      |> String.replace(~r/\s+/, " ")

    %{field: code}
  end

  test "enabled: false and disabled: true both disable the field", %{field: field} do
    assert field =~
             ~s|val enabled = boolProp(node.props, "enabled") != false && boolProp(node.props, "disabled") != true|

    assert field =~ "enabled = enabled,"
  end

  test "max_length rejects an over-long edit before it is shown or sent", %{field: field} do
    assert field =~ ~s|val maxLength = intProp(node.props, "max_length") ?: 0|

    # Only a lengthening edit is refused, so a value set past the limit can
    # still be shortened.
    assert field =~
             "onValueChange = onValueChange@{ new -> if (maxLength > 0 && new.text.length > maxLength && new.text.length > field.text.length) { return@onValueChange }"
  end

  test "lines makes the field multi-line with return inserting a newline", %{field: field} do
    assert field =~ ~s|val lines = intProp(node.props, "lines") ?: 1|
    assert field =~ "else -> if (multiline) ImeAction.Default else ImeAction.Done"
    assert field =~ "singleLine = !multiline, minLines = if (multiline) lines else 1,"
    assert field =~ "maxLines = if (multiline) lines else 1,"
  end

  test "caret: end pins the caret on edit and on focus", %{field: field} do
    assert field =~ ~s|val caretAtEnd = (node.props["caret"] as? String) == "end"|

    assert field =~
             "field = if (caretAtEnd) new.copy(selection = TextRange(new.text.length)) else new"

    assert field =~
             "if (caretAtEnd) field = field.copy(selection = TextRange(field.text.length))"

    # Through the colors: M3's TextField re-provides LocalTextSelectionColors
    # from them, so an outer CompositionLocalProvider is overridden.
    assert field =~ "TextFieldDefaults.colors(selectionColors = selectionColors).copy("
    refute field =~ "CompositionLocalProvider(LocalTextSelectionColors"
  end

  test "underline: false, or a border of the field's own, removes the indicator",
       %{field: field} do
    assert field =~ ~s|val underline = boolProp(node.props, "underline") ?: !drawsOwnBorder|
    assert field =~ "val indicator = if (underline) Color.Unspecified else Color.Transparent"

    for slot <- ~w(focusedIndicatorColor unfocusedIndicatorColor disabledIndicatorColor) do
      assert field =~ "#{slot} = indicator,"
    end
  end

  test "theme colours reach the field; the caret follows the text by default",
       %{field: field} do
    assert field =~
             "val fieldColors = TextFieldDefaults.colors(selectionColors = selectionColors).copy("

    assert field =~ "focusedTextColor = textColor,"
    assert field =~ "unfocusedPlaceholderColor = placeholderColor,"
    assert field =~ "unfocusedContainerColor = background,"

    assert field =~
             ~s|val caretColor = colorProp(node.props, "caret_color").takeOrElse { textColor }|

    assert field =~ "cursorColor = caretColor,"
    assert field =~ "colors = fieldColors,"
  end

  test "type props and text_align style the text and the placeholder", %{field: field} do
    assert field =~ "textAlign = textAlignProp(node.props) ?: baseStyle.textAlign,"

    assert field =~
             "fontFamily = fontFamilyProp(node.props, LocalContext.current) ?: baseStyle.fontFamily,"

    assert field =~ "letterSpacing = letterSpacing?.sp ?: baseStyle.letterSpacing,"
    assert field =~ "textStyle = fieldStyle,"
    assert field =~ "style = fieldStyle,"
  end
end
