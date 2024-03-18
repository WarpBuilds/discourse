import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { gt } from "truth-helpers";
import DButton from "discourse/components/d-button";
import { popupAjaxError } from "discourse/lib/ajax-error";
import dIcon from "discourse-common/helpers/d-icon";
import i18n from "discourse-common/helpers/i18n";
import { cloneJSON } from "discourse-common/lib/object";
import I18n from "discourse-i18n";
import FieldInput from "./field";

class Node {
  @tracked text;
  object;
  schema;
  index;
  active = false;
  parentTree;
  trees = [];

  constructor({ text, index, object, schema, parentTree }) {
    this.text = text;
    this.index = index;
    this.object = object;
    this.schema = schema;
    this.parentTree = parentTree;
  }
}

class Tree {
  propertyName = null;
  nodes = [];
}

export default class SchemaThemeSettingEditor extends Component {
  @service router;
  @tracked activeIndex = 0;
  @tracked backButtonText;
  @tracked saveButtonDisabled = false;

  data = cloneJSON(this.args.setting.value);
  history = [];
  schema = this.args.setting.objects_schema;

  @cached
  get tree() {
    let schema = this.schema;
    let data = this.data;
    let tree = new Tree();

    for (const point of this.history) {
      tree.propertyName = point.propertyName;
      data = data[point.node.index][point.propertyName];
      schema = schema.properties[point.propertyName].schema;
    }

    data.forEach((object, index) => {
      const node = new Node({
        index,
        schema,
        object,
        text: object[schema.identifier] || `${schema.name} ${index + 1}`,
        parentTree: tree,
      });

      if (index === this.activeIndex) {
        node.active = true;

        const childObjectsProperties = this.findChildObjectsProperties(
          schema.properties
        );

        for (const childObjectsProperty of childObjectsProperties) {
          const subtree = new Tree();
          subtree.propertyName = childObjectsProperty.name;

          data[index][childObjectsProperty.name]?.forEach(
            (childObj, childIndex) => {
              subtree.nodes.push(
                new Node({
                  text:
                    childObj[childObjectsProperty.schema.identifier] ||
                    `${childObjectsProperty.schema.name} ${childIndex + 1}`,
                  index: childIndex,
                  object: childObj,
                  schema: childObjectsProperty.schema,
                  parentTree: subtree,
                })
              );
            }
          );

          node.trees.push(subtree);
        }
      }

      tree.nodes.push(node);
    });

    return tree;
  }

  @cached
  get activeNode() {
    return this.tree.nodes.find((node, index) => {
      return index === this.activeIndex;
    });
  }

  get fields() {
    const node = this.activeNode;
    const list = [];

    for (const [name, spec] of Object.entries(node.schema.properties)) {
      if (spec.type === "objects") {
        continue;
      }

      list.push({
        name,
        spec,
        value: node.object[name],
        description: this.fieldDescription(name),
      });
    }

    return list;
  }

  findChildObjectsProperties(properties) {
    const list = [];

    for (const [name, spec] of Object.entries(properties)) {
      if (spec.type === "objects") {
        list.push({
          name,
          schema: spec.schema,
        });
      }
    }

    return list;
  }

  @action
  saveChanges() {
    this.saveButtonDisabled = true;

    this.args.setting
      .updateSetting(this.args.themeId, this.data)
      .then((result) => {
        this.args.setting.set("value", result[this.args.setting.setting]);

        this.router.transitionTo(
          "adminCustomizeThemes.show",
          this.args.themeId
        );
      })
      .catch(popupAjaxError)
      .finally(() => (this.saveButtonDisabled = false));
  }

  @action
  onClick(node) {
    this.activeIndex = node.index;
  }

  @action
  onChildClick(node, tree, parentNode) {
    this.history.push({
      propertyName: tree.propertyName,
      node: parentNode,
    });

    this.backButtonText = I18n.t("admin.customize.theme.schema.back_button", {
      name: parentNode.text,
    });

    this.activeIndex = node.index;
  }

  @action
  backButtonClick() {
    const historyPoint = this.history.pop();
    this.activeIndex = historyPoint.node.index;

    if (this.history.length > 0) {
      this.backButtonText = I18n.t("admin.customize.theme.schema.back_button", {
        name: this.history[this.history.length - 1].node.text,
      });
    } else {
      this.backButtonText = null;
    }
  }

  @action
  inputFieldChanged(field, newVal) {
    if (field.name === this.activeNode.schema.identifier) {
      this.activeNode.text = newVal;
    }

    this.activeNode.object[field.name] = newVal;
  }

  fieldDescription(fieldName) {
    const descriptions = this.args.setting.objects_schema_property_descriptions;

    if (!descriptions) {
      return;
    }

    let key;

    if (this.activeNode.parentTree.propertyName) {
      key = `${this.activeNode.parentTree.propertyName}.${fieldName}`;
    } else {
      key = `${fieldName}`;
    }

    return descriptions[key];
  }

  <template>
    <div class="schema-theme-setting-editor">
      <div class="schema-theme-setting-editor__navigation">
        <ul class="schema-theme-setting-editor__tree">
          {{#if this.backButtonText}}
            <li
              role="link"
              class="schema-theme-setting-editor__tree-node--back-btn"
              {{on "click" this.backButtonClick}}
            >
              <div class="schema-theme-setting-editor__tree-node-text">
                {{dIcon "chevron-left"}}
                {{this.backButtonText}}
              </div>
            </li>
          {{/if}}

          {{#each this.tree.nodes as |node|}}
            <li
              role="link"
              class="schema-theme-setting-editor__tree-node --parent
                {{if node.active ' --active'}}"
              {{on "click" (fn this.onClick node)}}
            >
              <div class="schema-theme-setting-editor__tree-node-text">
                {{node.text}}

                {{#if (gt node.trees.length 0)}}
                  {{dIcon (if node.active "chevron-down" "chevron-right")}}
                {{/if}}
              </div>
            </li>

            {{#each node.trees as |nestedTree|}}
              {{#if (gt nestedTree.nodes.length 0)}}
                <li
                  class="schema-theme-setting-editor__tree-node --child --heading"
                  data-test-parent-index={{node.index}}
                >
                  <div class="schema-theme-setting-editor__tree-node-text">
                    {{nestedTree.propertyName}}
                  </div>
                </li>
              {{/if}}

              {{#each nestedTree.nodes as |childNode|}}
                <li
                  role="link"
                  class="schema-theme-setting-editor__tree-node --child"
                  {{on
                    "click"
                    (fn this.onChildClick childNode nestedTree node)
                  }}
                  data-test-parent-index={{node.index}}
                >
                  <div class="schema-theme-setting-editor__tree-node-text">
                    {{childNode.text}}
                    {{dIcon "chevron-right"}}
                  </div>
                </li>
              {{/each}}
            {{/each}}
          {{/each}}
        </ul>
      </div>

      <div class="schema-theme-setting-editor__fields">
        {{#each this.fields as |field|}}
          <FieldInput
            @name={{field.name}}
            @value={{field.value}}
            @spec={{field.spec}}
            @onValueChange={{fn this.inputFieldChanged field}}
            @description={{field.description}}
          />
        {{/each}}
      </div>

      <div class="schema-theme-setting-editor__footer">
        <DButton
          @disabled={{this.saveButtonDisabled}}
          @action={{this.saveChanges}}
          @label="save"
          class="btn-primary"
        />

        <LinkTo
          @route="adminCustomizeThemes.show"
          @model={{@themeId}}
          class="btn-transparent"
        >
          {{i18n "cancel"}}
        </LinkTo>
      </div>
    </div>
  </template>
}
